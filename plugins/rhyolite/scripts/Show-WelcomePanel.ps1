#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [ValidateSet('Panel', 'Progress', 'PromptPlaque')]
    [string] $Mode = 'Panel'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $encoding
    $writer = [System.IO.StreamWriter]::new(
        [Console]::OpenStandardOutput(),
        $encoding,
        1024,
        $true
    )
    try {
        $writer.NewLine = "`n"
        $writer.Write($Text)
        if (-not $Text.EndsWith("`n")) {
            $writer.Write("`n")
        }
        $writer.Flush()
    }
    finally {
        $writer.Dispose()
    }
}

function Test-ColorEnabled {
    return (
        $null -eq $env:NO_COLOR -and
        $env:COPILOT_NO_COLOR -ne '1' -and
        $env:FORCE_COLOR -ne '0' -and
        $env:TERM -ne 'dumb'
    )
}

function Test-LauncherStartedImmediately {
    return (
        $env:RHYOLITE_LAUNCHER_IMMEDIATE_START -eq
        'RHYOLITE_LAUNCHER_IMMEDIATE_START_V1'
    )
}

function Test-PublicRepositoryUrlsResolved {
    foreach ($value in @(
        $script:metadata.homeUrl
        $script:metadata.docsUrl
        $script:metadata.supportUrl
        $script:metadata.issuesUrl
        $script:metadata.pullsUrl
    )) {
        if (
            [string]::IsNullOrWhiteSpace([string] $value) -or
            [Text.RegularExpressions.Regex]::IsMatch(
                [string] $value,
                '<PUBLIC_[A-Z0-9_:-]+>'
            )
        ) {
            return $false
        }
    }

    return $true
}

function Get-BannerDisplayWidth {
    $maxWidth = 0
    foreach ($bannerLine in (
        $script:banner.TrimEnd("`r", "`n") -split "`r?`n"
    )) {
        if ($bannerLine.Length -gt $maxWidth) {
            $maxWidth = $bannerLine.Length
        }
    }
    return $maxWidth
}

function Get-VersionLineText {
    $versionText = "v$($script:pluginVersion)"
    $padding = [Math]::Max(0, $script:bannerWidth - $versionText.Length)
    return (' ' * $padding) + $versionText
}

function Get-ReviewPlaque {
    $bannerLines = [Collections.Generic.List[string]]::new()
    foreach ($bannerLine in (
        $script:banner.TrimEnd("`r", "`n") -split "`r?`n"
    )) {
        $bannerLines.Add($bannerLine)
    }
    $plaqueLines = [Collections.Generic.List[string]]::new()
    $plaqueLines.Add((Get-VersionLineText))
    $plaqueLines.Add('')
    $plaqueLines.Add(
        'Rhyolite guides evidence-based, read-only reviews of public HTTPS Git repositories.'
    )
    $plaqueLines.Add('Use /rhyolite:start to begin a review.')
    $plaqueLines.Add(
        'Use /rhyolite:help for commands or /rhyolite:status for current progress.'
    )
    $colors = @(
        '118;234;255'
        '90;220;255'
        '66;203;255'
        '54;182;255'
        '68;148;248'
        '88;122;230'
    )
    if (-not (Test-ColorEnabled)) {
        return (@($bannerLines) + @($plaqueLines)) -join "`n"
    }

    $escape = [char] 27
    $coloredBanner = for ($index = 0; $index -lt $bannerLines.Count; $index++) {
        $color = $colors[$index % $colors.Count]
        "$escape[38;2;${color}m$($bannerLines[$index])$escape[0m"
    }
    $versionColor = $colors[$colors.Count - 1]
    $coloredVersionLine =
        "$escape[38;2;${versionColor}m$(Get-VersionLineText)$escape[0m"
    return (
        @($coloredBanner) +
        @($coloredVersionLine) +
        @($plaqueLines | Select-Object -Skip 1)
    ) -join "`n"
}

$scriptDirectory = Split-Path -Parent $PSCommandPath
$pluginRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDirectory '..')).Path
$metadataPath = Join-Path $pluginRoot 'branding/welcome-metadata.json'
$pluginManifestPath = Join-Path $pluginRoot 'plugin.json'

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$script:metadata = $metadata
$pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw |
    ConvertFrom-Json
$script:displayName = [string] $metadata.displayName
$script:pluginVersion = [string] $pluginManifest.version
$bannerPath = Join-Path $pluginRoot $metadata.bannerAssetPath
$banner = Get-Content -LiteralPath $bannerPath -Raw
$script:bannerWidth = Get-BannerDisplayWidth

if ($Mode -eq 'Progress') {
    if (Test-LauncherStartedImmediately) {
        return
    }
    $progress = [ordered]@{
        type = 'progress'
        message = (
            "$($metadata.displayName) v$($pluginManifest.version) loaded — " +
            "type $($metadata.startCommand) to start."
        )
    } | ConvertTo-Json -Compress
    Write-Utf8Lf -Text $progress
    return
}

if ($Mode -eq 'PromptPlaque') {
    $hookInput = [Console]::In.ReadToEnd()
    if ($hookInput.Contains('RHYOLITE_START_COMMAND_V1') -or
        $hookInput.Contains('/rhyolite:start') -or
        $hookInput.Contains('/rhyolite:repo-review') -or
        $hookInput.Contains('/repo-review')) {
        $progress = [ordered]@{
            type = 'progress'
            message = Get-ReviewPlaque
        } | ConvertTo-Json -Compress
        Write-Utf8Lf -Text $progress
    }
    return
}

$helpPhrase = $metadata.setupHelpPhrases[0]
$statusPhrase = $metadata.setupHelpPhrases[1]
$explainScopesPhrase = $metadata.setupHelpPhrases[2]
$documentationLine = if (Test-PublicRepositoryUrlsResolved) {
    "Docs: $($metadata.docsUrl)"
}
else {
    "Docs: $($metadata.localDocsPath) (local distribution documentation)"
}
$supportLine = if (Test-PublicRepositoryUrlsResolved) {
    "Support: $($metadata.supportUrl)"
}
else {
    (
        "Support: $($metadata.localSupportPath) " +
        '(local source/distribution documentation)'
    )
}
$panel = @(
    $banner.TrimEnd("`r", "`n")
    (Get-VersionLineText)
    $metadata.tagline
    ''
    'Stage: Setup'
    'Scope: NOT SELECTED'
    ''
    "Start: Type $($metadata.startCommand) to begin guided setup."
    "Shorthand: Type $($metadata.shortStartCommand) when extension commands are available."
    "Agent fallback: Type /agent $($metadata.startAgentId), then type start."
    'Commands: /rhyolite:help | /rhyolite:status | /rhyolite:version'
    "Rhyolite help: Type $helpPhrase without a leading slash to re-show setup guidance."
    "Rhyolite status: Type $statusPhrase without a leading slash to see current selections."
    "Explain scopes: Type $explainScopesPhrase without a leading slash for scope 1/2/3 setup differences."
    ''
    $documentationLine
    $supportLine
) -join "`n"

Write-Utf8Lf -Text $panel
