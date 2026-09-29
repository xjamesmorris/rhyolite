param(
    [string] $FirstArgument
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$CommandArguments = @()
if (-not [string]::IsNullOrWhiteSpace($FirstArgument)) {
    $CommandArguments += $FirstArgument
}
if ($args.Count -gt 0) {
    $CommandArguments += $args
}

$RhyoliteAgent = 'rhyolite:repo-review'
$RhyoliteStartMarker = 'RHYOLITE_START_COMMAND_V1'
$RhyoliteLauncherImmediateStartMarker = 'RHYOLITE_LAUNCHER_IMMEDIATE_START_V1'
$script:RhyoliteSupportText = 'SUPPORT.md and local documentation'
$script:RhyoliteContributeText = 'CONTRIBUTING.md'

function Fail {
    param(
        [Parameter(Mandatory)]
        [string] $Stage,

        [Parameter(Mandatory)]
        [string] $Summary,

        [Parameter(Mandatory)]
        [string] $Details,

        [Parameter(Mandatory)]
        [string] $Remediation,

        [int] $ExitCode = 1,

        [string] $Artifacts = 'NONE'
    )

    $safeDetails = [regex]::Replace(
        $Details,
        '(?:\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|' +
            '\x1B\[[0-?]*[ -/]*[@-~]|\x1B[@-_])',
        ''
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '[\x00-\x08\x0B-\x1F\x7F]',
        ''
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '(?i)(https?://)[^/@\s]+:[^/@\s]+@',
        '$1[credentials omitted]@'
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '(?i)((?:proxy-)?authorization\s*:\s*(?:bearer|basic)?\s*)\S+',
        '$1[credential omitted]'
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '(?i)((?:access[_-]?token|api[_-]?key|password|secret|token)' +
            '\s*[:=]\s*)\S+',
        '$1[credential omitted]'
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}\b',
        '[credential omitted]'
    )
    $safeDetails = [regex]::Replace(
        $safeDetails,
        '(?i)(?<![A-Z0-9._%+-])' +
            '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}' +
            '(?![A-Z0-9._%+-])',
        '[email omitted]'
    )
    $safeDetails = ($safeDetails -replace "`r?`n", ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($safeDetails)) {
        $safeDetails = 'No additional safe detail was returned.'
    }

    $errorText = @(
        'RHYOLITE ERROR'
        "Summary: $Summary"
        "Stage: $Stage"
        'Source: NOT APPLICABLE'
        "Details: $safeDetails (exit code $ExitCode)"
        'Consequence: Copilot and guided repository-review setup did not start or complete.'
        "Remediation: $Remediation"
        "Artifacts: $Artifacts"
        "Support: $script:RhyoliteSupportText"
        "Contribute: $script:RhyoliteContributeText"
    ) -join "`n"
    [Console]::Error.WriteLine($errorText)
    exit $ExitCode
}

function Set-RepositorySupportLinks {
    param(
        [Parameter(Mandatory)]
        [string] $PluginRoot
    )

    $metadataPath = Join-Path $PluginRoot 'branding\welcome-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return
    }
    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw |
            ConvertFrom-Json
        $repositoryUrls = @(
            [string] $metadata.homeUrl
            [string] $metadata.docsUrl
            [string] $metadata.supportUrl
            [string] $metadata.issuesUrl
            [string] $metadata.pullsUrl
        )
        $issuesUrl = [string] $metadata.issuesUrl
        $pullsUrl = [string] $metadata.pullsUrl
        if (@(
                $repositoryUrls |
                    Where-Object {
                        [string]::IsNullOrWhiteSpace($_) -or
                        [Text.RegularExpressions.Regex]::IsMatch(
                            $_,
                            '<PUBLIC_[A-Z0-9_:-]+>'
                        )
                    }
            ).Count -eq 0) {
            $script:RhyoliteSupportText = $issuesUrl
            $script:RhyoliteContributeText = $pullsUrl
        }
    }
    catch {
        return
    }
}

function Invoke-ArgumentPreservingProcess {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    foreach ($argument in $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) {
        throw "Could not start process: $FilePath"
    }
    try {
        $process.WaitForExit()
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

trap {
    Fail `
        -Stage 'launcher runtime' `
        -Summary 'The launcher encountered an unexpected local setup failure.' `
        -Details $_.Exception.ToString() `
        -Remediation 'Correct the reported path, permission, or installation problem and retry.' `
        -ExitCode 1
}

function Resolve-PhysicalPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $item = $item.ResolveLinkTarget($true)
    }

    return [IO.Path]::GetFullPath($item.FullName)
}

function Read-PluginVersion {
    param(
        [Parameter(Mandatory)]
        [string] $PluginRoot
    )

    $pluginJsonPath = Join-Path $PluginRoot 'plugin.json'
    $plugin = Get-Content -LiteralPath $pluginJsonPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($plugin.version)) {
        Fail `
            -Stage 'plugin validation' `
            -Summary 'The installed plugin version is unavailable.' `
            -Details "Could not read version from $pluginJsonPath." `
            -Remediation 'Restore a valid plugin.json, then retry the launcher.' `
            -ExitCode 2
    }

    return [string] $plugin.version
}

function Get-StateHome {
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    }

    $localAppData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        return [IO.Path]::GetFullPath($localAppData)
    }

    return [IO.Path]::Combine($HOME, 'AppData', 'Local')
}

function Assert-ControlFreePath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path -match '[\x00-\x1F\x7F]') {
        Fail `
            -Stage 'launcher path validation' `
            -Summary 'A required launcher path contains control characters.' `
            -Details "Rejected path: $Path" `
            -Remediation 'Move the checkout or working directory to a control-free path and retry.' `
            -ExitCode 2
    }
}

function Test-GitMarker {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return Test-Path -LiteralPath (Join-Path $Path '.git')
}

function Get-CleanLaunchDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $OriginalDirectory
    )

    $cursor = [IO.Path]::GetFullPath($OriginalDirectory)
    $lastGitRoot = $null

    while ($true) {
        if (Test-GitMarker -Path $cursor) {
            $lastGitRoot = $cursor
        }

        $parentInfo = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parentInfo) {
            break
        }

        $parent = $parentInfo.FullName
        if ([string]::Equals($parent, $cursor, [StringComparison]::Ordinal)) {
            break
        }

        $cursor = $parent
    }

    if ($null -ne $lastGitRoot) {
        $parentInfo = [IO.Directory]::GetParent($lastGitRoot)
        if ($null -eq $parentInfo) {
            Fail `
                -Stage 'clean launch directory selection' `
                -Summary 'A safe non-Git launch directory could not be derived.' `
                -Details "The Git worktree root $lastGitRoot has no usable parent directory." `
                -Remediation 'Run the launcher from a normal filesystem location outside the target worktree.' `
                -ExitCode 2
        }
        return $parentInfo.FullName
    }

    return $OriginalDirectory
}

function New-LauncherSessionDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $LauncherRoot
    )

    $sessionsRoot = Join-Path $LauncherRoot 'Sessions'
    [IO.Directory]::CreateDirectory($sessionsRoot) | Out-Null

    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $attempt = 0
    while ($true) {
        $sessionId = "$timestamp-$PID"
        if ($attempt -gt 0) {
            $sessionId = "$sessionId-$attempt"
        }

        $candidate = Join-Path $sessionsRoot $sessionId
        if (-not (Test-Path -LiteralPath $candidate)) {
            [IO.Directory]::CreateDirectory($candidate) | Out-Null
            return $candidate
        }

        $attempt++
    }
}

function Join-InitialRequest {
    param([string[]] $Parts)

    $Parts = @($Parts)
    $sanitizedParts = [System.Collections.Generic.List[string]]::new()
    foreach ($part in $Parts) {
        $sanitized = [regex]::Replace($part, '[\x00-\x1F\x7F]', '')
        if (-not [string]::IsNullOrWhiteSpace($sanitized)) {
            $sanitizedParts.Add($sanitized)
        }
    }

    return ($sanitizedParts -join ' ')
}

function Get-RemainingArguments {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $Arguments = @($Arguments)
    if ($Arguments.Count -le 1) {
        return @()
    }

    return ,($Arguments[1..($Arguments.Count - 1)])
}

function Build-InitialPrompt {
    param([string] $InitialRequest)

    if (-not [string]::IsNullOrWhiteSpace($InitialRequest)) {
        return @"
$RhyoliteStartMarker
Begin Rhyolite's guided repository-review setup now.
Treat the following text as the user's initial review request:

$InitialRequest
"@
    }

    return @"
$RhyoliteStartMarker
Begin Rhyolite's guided repository-review setup now.
"@
}

function Write-LaunchContext {
    param(
        [Parameter(Mandatory)]
        [string] $ContextPath,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $OriginalDirectory,

        [Parameter(Mandatory)]
        [string] $LaunchDirectory,

        [Parameter(Mandatory)]
        [string] $PluginRoot
    )

    @(
        "StartedAtUtc=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "Version=$Version"
        "OriginalWorkingDirectory=$OriginalDirectory"
        "LaunchDirectory=$LaunchDirectory"
        "PluginRoot=$PluginRoot"
    ) | Set-Content -LiteralPath $ContextPath -Encoding utf8NoBOM
}

function Write-HelpText {
    param(
        [Parameter(Mandatory)]
        [string] $Version
    )

    @"
Rhyolite launcher v$Version

Usage:
  rhyolite.ps1 [--help]
  rhyolite.ps1 [--version]
  rhyolite.ps1 [--] [initial review request...]

Starts Copilot outside Git worktrees with the checkout-loaded Rhyolite plugin,
selects $RhyoliteAgent, and begins guided setup immediately.
"@
}

$scriptPath = Resolve-PhysicalPath -Path $PSCommandPath
$scriptDirectory = Split-Path -Parent $scriptPath
$pluginRoot = [IO.Path]::GetFullPath((Join-Path $scriptDirectory '..'))
Set-RepositorySupportLinks -PluginRoot $pluginRoot

if (-not (Test-Path -LiteralPath (Join-Path $pluginRoot 'plugin.json') -PathType Leaf)) {
    Fail `
        -Stage 'plugin validation' `
        -Summary 'Required plugin metadata is missing.' `
        -Details "Plugin metadata was not found under $pluginRoot." `
        -Remediation 'Restore the complete Rhyolite plugin installation and retry.' `
        -ExitCode 2
}
if (-not (Test-Path -LiteralPath (Join-Path $pluginRoot 'commands/start.md') -PathType Leaf)) {
    Fail `
        -Stage 'plugin validation' `
        -Summary 'The Rhyolite start command is missing.' `
        -Details "Start command was not found under $pluginRoot." `
        -Remediation 'Restore the complete Rhyolite plugin installation and retry.' `
        -ExitCode 2
}
if (-not (Test-Path -LiteralPath (Join-Path $pluginRoot 'agents/repo-review.agent.md') -PathType Leaf)) {
    Fail `
        -Stage 'plugin validation' `
        -Summary 'The Rhyolite review agent is missing.' `
        -Details "Repo-review agent was not found under $pluginRoot." `
        -Remediation 'Restore the complete Rhyolite plugin installation and retry.' `
        -ExitCode 2
}

$pluginVersion = Read-PluginVersion -PluginRoot $pluginRoot

$rawCommandLineArguments = @([Environment]::GetCommandLineArgs())
$scriptArgumentIndex = [Array]::IndexOf(
    $rawCommandLineArguments,
    $PSCommandPath
)
if ($scriptArgumentIndex -ge 0) {
    $rawCommandLineArguments = if (
        $scriptArgumentIndex + 1 -lt $rawCommandLineArguments.Count
    ) {
        $rawCommandLineArguments[($scriptArgumentIndex + 1)..(
            $rawCommandLineArguments.Count - 1
        )]
    }
    else {
        @()
    }
}

if ($rawCommandLineArguments -contains '--help' -or
    $rawCommandLineArguments -contains '-h') {
    Write-Output (Write-HelpText -Version $pluginVersion)
    exit 0
}

if ($rawCommandLineArguments -contains '--version' -or
    $rawCommandLineArguments -contains '-v') {
    Write-Output "Rhyolite v$pluginVersion"
    exit 0
}

$mode = 'launch'
if ($CommandArguments.Count -gt 0 -and $CommandArguments[0] -in @('--help', '-h')) {
    $mode = 'help'
    $CommandArguments = if ($CommandArguments.Count -gt 1) {
        Get-RemainingArguments -Arguments $CommandArguments
    }
    else {
        @()
    }
}
elseif ($CommandArguments.Count -gt 0 -and $CommandArguments[0] -in @('--version', '-v')) {
    $mode = 'version'
    $CommandArguments = if ($CommandArguments.Count -gt 1) {
        Get-RemainingArguments -Arguments $CommandArguments
    }
    else {
        @()
    }
}

if ($mode -eq 'help') {
    if (@($CommandArguments).Count -ne 0) {
        Fail `
            -Stage 'launcher argument validation' `
            -Summary 'The help request included unsupported extra arguments.' `
            -Details '--help does not accept additional arguments.' `
            -Remediation 'Run rhyolite.ps1 --help without any other arguments.' `
            -ExitCode 2
    }
    Write-Output (Write-HelpText -Version $pluginVersion)
    exit 0
}

if ($mode -eq 'version') {
    if (@($CommandArguments).Count -ne 0) {
        Fail `
            -Stage 'launcher argument validation' `
            -Summary 'The version request included unsupported extra arguments.' `
            -Details '--version does not accept additional arguments.' `
            -Remediation 'Run rhyolite.ps1 --version without any other arguments.' `
            -ExitCode 2
    }
    Write-Output "Rhyolite v$pluginVersion"
    exit 0
}

if (@($CommandArguments).Count -gt 0 -and @($CommandArguments)[0] -eq '--') {
    $CommandArguments = if ($CommandArguments.Count -gt 1) {
        Get-RemainingArguments -Arguments $CommandArguments
    }
    else {
        @()
    }
}

$copilotCommand = if ($IsWindows) {
    Get-Command copilot `
        -CommandType ExternalScript `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
else {
    $null
}
if ($null -eq $copilotCommand) {
    $copilotCommand = Get-Command copilot `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if ($null -eq $copilotCommand) {
    $copilotCommand = Get-Command copilot `
        -CommandType ExternalScript `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if ($null -eq $copilotCommand) {
    Fail `
        -Stage 'Copilot CLI discovery' `
        -Summary 'The GitHub Copilot CLI is not available.' `
        -Details "The 'copilot' executable was not found on PATH." `
        -Remediation 'Install GitHub Copilot CLI or add it to PATH, then retry.' `
        -ExitCode 127
}

$originalDirectory = [IO.Path]::GetFullPath((Get-Location).Path)
$originalDirectory = Resolve-PhysicalPath -Path $originalDirectory
$pluginRoot = Resolve-PhysicalPath -Path $pluginRoot

Assert-ControlFreePath -Path $originalDirectory
Assert-ControlFreePath -Path $pluginRoot

$launchDirectory = Get-CleanLaunchDirectory -OriginalDirectory $originalDirectory
$launchDirectory = Resolve-PhysicalPath -Path $launchDirectory
Assert-ControlFreePath -Path $launchDirectory
if (Test-GitMarker -Path $launchDirectory) {
    Fail `
        -Stage 'clean launch directory selection' `
        -Summary 'The selected orchestration directory is still a Git worktree.' `
        -Details "Refusing to start inside $launchDirectory." `
        -Remediation 'Start Rhyolite from a directory outside every Git worktree.' `
        -ExitCode 2
}

$stateHome = Get-StateHome
$launcherRoot = Join-Path $stateHome 'Rhyolite\Launcher'
$sessionDirectory = New-LauncherSessionDirectory -LauncherRoot $launcherRoot
$logDirectory = Join-Path $sessionDirectory 'copilot-logs'
[IO.Directory]::CreateDirectory($logDirectory) | Out-Null

$initialRequest = Join-InitialRequest -Parts $CommandArguments
$initialPrompt = Build-InitialPrompt -InitialRequest $initialRequest

Write-LaunchContext `
    -ContextPath (Join-Path $sessionDirectory 'launch-context.txt') `
    -Version $pluginVersion `
    -OriginalDirectory $originalDirectory `
    -LaunchDirectory $launchDirectory `
    -PluginRoot $pluginRoot

$env:RHYOLITE_LAUNCHER_CALLER_DIR = $originalDirectory
$env:RHYOLITE_LAUNCHER_LAUNCH_DIR = $launchDirectory
$env:RHYOLITE_LAUNCHER_PLUGIN_ROOT = $pluginRoot
$env:RHYOLITE_LAUNCHER_SESSION_DIR = $sessionDirectory
$env:RHYOLITE_LAUNCHER_VERSION = $pluginVersion
$env:RHYOLITE_LAUNCHER_IMMEDIATE_START =
    $RhyoliteLauncherImmediateStartMarker

$copilotArguments = @(
    '--experimental'
    '-C'
    $launchDirectory
    '--plugin-dir'
    $pluginRoot
    '--agent'
    $RhyoliteAgent
    '--log-dir'
    $logDirectory
    '--no-custom-instructions'
    '-i'
    $initialPrompt
)

$copilotExecutablePath = $copilotCommand.Source
if ($copilotCommand.CommandType -eq 'ExternalScript') {
    $copilotWrapperCandidate = Join-Path `
        (Split-Path -Parent $copilotExecutablePath) `
        ([IO.Path]::GetFileNameWithoutExtension($copilotExecutablePath))
    if (Test-Path -LiteralPath $copilotWrapperCandidate -PathType Leaf) {
        $copilotExecutablePath = $copilotWrapperCandidate
    }
}

$currentPowerShellPath = (Get-Process -Id $PID).Path
$copilotExitCode = 1
Push-Location $launchDirectory
try {
    if ($copilotExecutablePath -ne $copilotCommand.Source) {
        & $copilotExecutablePath @copilotArguments
        $copilotExitCode = $LASTEXITCODE
    }
    elseif ($copilotCommand.CommandType -eq 'ExternalScript') {
        $copilotLauncherArguments = @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-File'
            $copilotCommand.Source
        ) + $copilotArguments
        $copilotExitCode = Invoke-ArgumentPreservingProcess `
            -FilePath $currentPowerShellPath `
            -Arguments $copilotLauncherArguments `
            -WorkingDirectory $launchDirectory
    }
    else {
        & $copilotExecutablePath @copilotArguments
        $copilotExitCode = $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
if ($copilotExitCode -ne 0) {
    Fail `
        -Stage 'Copilot session' `
        -Summary 'The Copilot CLI session exited before Rhyolite completed normally.' `
        -Details "Copilot CLI returned exit code $copilotExitCode." `
        -Remediation 'Review the launcher logs, address the reported Copilot failure, and retry from a clean non-Git directory.' `
        -ExitCode $copilotExitCode `
        -Artifacts (
            (Join-Path $sessionDirectory 'launch-context.txt') +
            "; $logDirectory"
        )
}
exit $copilotExitCode
