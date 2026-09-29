[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(ParameterSetName = 'Direct')]
    [ValidateNotNullOrEmpty()]
    [string[]] $Repository = @(),

    [Parameter(ParameterSetName = 'Direct')]
    [ValidateNotNullOrEmpty()]
    [string[]] $RepositoryPath = @(),

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $RepositoryListPath,

    [ValidateRange(1, 8)]
    [int] $ThrottleLimit = 2,

    [ValidateRange(1, 10)]
    [int] $MaxRepositories = 5,

    [ValidateRange(0, 720)]
    [int] $SessionTimeoutMinutes = 0,

    [ValidateNotNullOrEmpty()]
    [string] $WorkspaceRoot = [IO.Path]::Combine(
        $HOME,
        '.cache',
        'rhyolite',
        'repo-review',
        'workspaces'
    ),

    [Alias('ResultRoot')]
    [string] $OutputRoot = '',

    [AllowNull()]
    [object] $Scope = $null,

    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $Commit = '',

    [ValidateNotNullOrEmpty()]
    [string] $Model = 'gpt-5.6-sol',

    [switch] $EnablePublicResearch,

    [switch] $EnableProvenanceResearch,

    [AllowNull()]
    [object] $ProvenanceLookbackMonths = $null,

    [switch] $NonInteractive,

    [switch] $OpenHtml,

    [switch] $NoOpenHtml,

    [switch] $ValidateOnly,

    [switch] $PlanOnly,

    [string] $ExpectedPlanHash = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$defaultPriorArtLookbackMonths = 6
$defaultProvenanceLookbackMonths = 6
$planSchemaVersion = 1
$stateSchemaVersion = 3
$script:RhyoliteSupportText = 'SUPPORT.md and local documentation'
$script:RhyoliteContributeText = 'CONTRIBUTING.md'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required.'
}

function Resolve-ApplicationPath {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $commands = @(Get-Command $Name -CommandType Application -All -ErrorAction Stop)
    if ($IsWindows) {
        $preferred = $commands |
            Where-Object {
                $_.Source.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
        if ($preferred) {
            return $preferred.Source
        }
    }

    return ($commands | Select-Object -First 1).Source
}

function Clear-InheritedGitEnvironment {
    $gitVariables = @(
        Get-ChildItem Env: |
            Where-Object Name -Like 'GIT_*'
    )
    foreach ($variable in $gitVariables) {
        Remove-Item -LiteralPath (
            Join-Path -Path 'Env:' -ChildPath $variable.Name
        ) -Force
    }

    $remaining = @(
        Get-ChildItem Env: |
            Where-Object Name -Like 'GIT_*'
    )
    if ($remaining.Count -gt 0) {
        $names = ($remaining.Name | Sort-Object) -join ', '
        throw "Could not remove inherited Git environment variables: $names"
    }
}

function Get-CopilotAuthenticationBridge {
    param(
        [Parameter(Mandatory)]
        [string] $CopilotHome
    )

    $emptyBridge = [pscustomobject]@{
        Json = '{}'
        HasPlaintextTokens = $false
    }
    if ([string]::IsNullOrWhiteSpace($CopilotHome)) {
        return $emptyBridge
    }

    $configPath = Join-Path $CopilotHome 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return $emptyBridge
    }

    try {
        $configText = [IO.File]::ReadAllText($configPath)
        $configText = [Text.RegularExpressions.Regex]::Replace(
            $configText,
            '(?m)^\s*//.*$',
            ''
        )
        $config = $configText | ConvertFrom-Json
        $bridge = [ordered]@{}
        foreach ($name in @(
            'lastLoggedInUser'
            'loggedInUsers'
            'copilotTokens'
            'last_logged_in_user'
            'logged_in_users'
            'copilot_tokens'
        )) {
            $property = $config.PSObject.Properties[$name]
            if ($null -ne $property) {
                $bridge[$name] = $property.Value
            }
        }

        $hasPlaintextTokens = $false
        foreach ($name in @('copilotTokens', 'copilot_tokens')) {
            $property = $config.PSObject.Properties[$name]
            if ($null -ne $property -and
                $null -ne $property.Value -and
                @($property.Value.PSObject.Properties).Count -gt 0) {
                $hasPlaintextTokens = $true
                break
            }
        }

        return [pscustomobject]@{
            Json = if ($bridge.Count -eq 0) {
                '{}'
            }
            else {
                $bridge | ConvertTo-Json -Depth 16
            }
            HasPlaintextTokens = $hasPlaintextTokens
        }
    }
    catch {
        return $emptyBridge
    }
}

function Test-InteractiveConsole {
    if ($NonInteractive) {
        return $false
    }

    try {
        return [Environment]::UserInteractive -and
            -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

function Get-DefaultOutputRoot {
    return [IO.Path]::Combine($HOME, 'rhyolite-output', 'repo-review')
}

function Get-UtcTimestamp {
    return [DateTimeOffset]::UtcNow.ToString(
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-ReviewPlanOpenHtmlPolicy {
    if ($OpenHtml) {
        return 'always'
    }
    if ($NoOpenHtml) {
        return 'never'
    }

    return 'default'
}

function Get-StatusWord {
    param(
        [Parameter(Mandatory)]
        [bool] $Enabled
    )

    if ($Enabled) {
        return 'enabled'
    }

    return 'disabled'
}

function Set-RhyoliteRepositorySupportLinks {
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

    function Get-RepositoryFailureStage {
        param(
            [Parameter(Mandatory)]
            [string] $Status,

            [AllowEmptyString()]
            [string] $Errors = ''
        )

        switch ($Status) {
            { $_ -in @('AccessPreflightFailed', 'PreflightBlocked') } {
                return 'anonymous repository preflight'
            }
            'CloneFailed' { return 'clone' }
            'CommitResolutionFailed' { return 'commit resolution' }
            'SnapshotFailed' { return 'read-only snapshot' }
            'TimedOut' { return 'worker timeout' }
            'ReviewFailed' {
                if ($Errors -match (
                    'temporary Copilot runtime home|' +
                    'sanitize the temporary Copilot|cleanup'
                )) {
                    return 'cleanup'
                }
                if ($Errors -match (
                    'Incomplete report|Final report extraction failed|' +
                    'Final report header|Markdown table'
                )) {
                    return 'report validation'
                }
                return 'worker analysis'
            }
            default { return 'finalization' }
        }
    }

    function Get-RepositoryFailureSummary {
        param(
            [Parameter(Mandatory)]
            [string] $Status,

            [Parameter(Mandatory)]
            [string] $Stage
        )

        switch ($Status) {
            'AccessPreflightFailed' {
                return 'Anonymous access to the selected public HTTPS repository could not be verified.'
            }
            'PreflightBlocked' {
                return 'This repository was not started because another selected source failed the fail-closed anonymous preflight.'
            }
            'CloneFailed' { return 'The anonymous public HTTPS clone failed.' }
            'CommitResolutionFailed' {
                return 'The requested exact commit could not be fetched, checked out, or verified.'
            }
            'SnapshotFailed' {
                return 'The trusted runner could not create the read-only, .git-free source snapshot.'
            }
            'TimedOut' {
                return 'The repository-review worker exceeded its configured time limit.'
            }
            'ReviewFailed' {
                if ($Stage -eq 'cleanup') {
                    return 'The review failed closed because temporary Copilot runtime cleanup did not complete safely.'
                }
                if ($Stage -eq 'report validation') {
                    return 'The worker response did not satisfy the complete canonical report contract.'
                }
                return 'The repository-review worker exited without a completed review.'
            }
            default { return 'The repository review did not complete.' }
        }
    }

    function Get-RepositoryFailureRemediation {
        param(
            [Parameter(Mandatory)]
            [string] $Status,

            [Parameter(Mandatory)]
            [string] $Stage
        )

        switch ($Status) {
            'AccessPreflightFailed' {
                return 'Supply an anonymously readable public HTTPS Git URL and retry. Rhyolite supports public sources only and intentionally does not attempt target authentication.'
            }
            'PreflightBlocked' {
                return 'Remove or correct every source that failed anonymous preflight, regenerate the plan, and rerun the whole approved selection.'
            }
            'CloneFailed' {
                return 'Verify the repository remains anonymously reachable over HTTPS, then retry; Rhyolite will not use target credentials.'
            }
            'CommitResolutionFailed' {
                return 'Verify that the exact 40-character commit is publicly reachable from the selected repository, regenerate the plan if needed, and retry.'
            }
            'SnapshotFailed' {
                return 'Check local Git/tar availability, free space, and workspace permissions, then retry without weakening snapshot isolation.'
            }
            'TimedOut' {
                return 'Retry with a larger runner timeout or a narrower review scope.'
            }
            'ReviewFailed' {
                if ($Stage -eq 'cleanup') {
                    return 'Securely remove the reported temporary runtime path, correct local permissions or locks, and retry.'
                }
                if ($Stage -eq 'report validation') {
                    return 'Rerun the review; use the saved timeline and errors artifacts to diagnose repeated incomplete output.'
                }
                return 'Review the sanitized errors and timeline. If they show Copilot authentication failure, run copilot login from a clean non-Git directory, then retry.'
            }
            default {
                return 'Inspect the returned state and errors artifacts, correct the reported local failure, and retry.'
            }
        }
    }

    function Write-RhyoliteRepositoryError {
        param(
            [Parameter(Mandatory)]
            [object] $Result
        )

        $errors = if (Test-Path -LiteralPath $Result.Errors -PathType Leaf) {
            ConvertTo-ReviewPlainText `
                -Text ([IO.File]::ReadAllText($Result.Errors)) `
                -RedactEmails `
                -RedactCredentials
        }
        else {
            ''
        }
        $details = @(
            $errors -split "`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        ) -join ' | '
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = 'No additional safe detail was returned.'
        }
        $stage = Get-RepositoryFailureStage `
            -Status ([string] $Result.Status) `
            -Errors $errors
        $summary = Get-RepositoryFailureSummary `
            -Status ([string] $Result.Status) `
            -Stage $stage
        $remediation = Get-RepositoryFailureRemediation `
            -Status ([string] $Result.Status) `
            -Stage $stage
        Write-Host ''
        @(
            'RHYOLITE ERROR'
            "Summary: $summary"
            "Stage: $stage"
            "Source: $($Result.Repository)"
            "Details: Status $($Result.Status); exit code $($Result.ExitCode); $details"
            'Consequence: This repository did not produce a completed review; the run state and artifacts remain truthful.'
            "Remediation: $remediation"
            (
                "Artifacts: State $($Result.State); Errors $($Result.Errors); " +
                "Timeline $($Result.Timeline); Handoff $($Result.Handoff)"
            )
            "Support: $script:RhyoliteSupportText"
            "Contribute: $script:RhyoliteContributeText"
        ) | ForEach-Object { Write-Host $_ }
}

function ConvertTo-Base64Utf8 {
    param(
        [AllowEmptyString()]
        [string] $Value = ''
    )

    $utf8 = [Text.UTF8Encoding]::new($false)
    return [Convert]::ToBase64String($utf8.GetBytes($Value))
}

function ConvertTo-ApprovalHashValue {
    param(
        [AllowNull()]
        [string] $Value = $null
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return 'null'
    }

    return 'base64:' + (ConvertTo-Base64Utf8 -Value $Value)
}

function ConvertTo-ApprovalHashMaterial {
    param(
        [Parameter(Mandatory)]
        [object[]] $Sources,

        [Parameter(Mandatory)]
        [string] $ReviewDate,

        [Parameter(Mandatory)]
        [string] $WorkspaceRoot,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [int] $ScopeNumber,

        [Parameter(Mandatory)]
        [string] $ScopeName,

        [Parameter(Mandatory)]
        [bool] $PublicResearch,

        [Parameter(Mandatory)]
        [bool] $ProvenanceResearch,

        [Parameter(Mandatory)]
        [psobject] $PriorArtWindow,

        [AllowNull()]
        [psobject] $ProvenanceWindow = $null,

        [Parameter(Mandatory)]
        [int] $SessionTimeoutMinutes,

        [Parameter(Mandatory)]
        [int] $ThrottleLimit,

        [Parameter(Mandatory)]
        [int] $MaxRepositories,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [string] $OpenHtmlPolicy
    )

    $lines = [Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($source in $Sources) {
        $lines.Add(
            "Source[$index].Kind=$(ConvertTo-ApprovalHashValue -Value ([string] $source.Kind))"
        )
        $lines.Add(
            "Source[$index].LocalPath=$(ConvertTo-ApprovalHashValue -Value ([string] $source.LocalPath))"
        )
        $lines.Add(
            "Source[$index].RemoteUrl=$(ConvertTo-ApprovalHashValue -Value ([string] $source.RemoteUrl))"
        )
        $lines.Add(
            "Source[$index].RequestedCommit=$(ConvertTo-ApprovalHashValue -Value ([string] $source.RequestedCommit))"
        )
        $lines.Add(
            "Source[$index].Slug=$(ConvertTo-ApprovalHashValue -Value ([string] $source.Slug))"
        )
        $index++
    }
    $lines.Add(
        "ReviewDate=$(ConvertTo-ApprovalHashValue -Value $ReviewDate)"
    )
    $lines.Add(
        "WorkspaceRoot=$(ConvertTo-ApprovalHashValue -Value $WorkspaceRoot)"
    )
    $lines.Add(
        "OutputRoot=$(ConvertTo-ApprovalHashValue -Value $OutputRoot)"
    )
    $lines.Add("Scope.Number=$ScopeNumber")
    $lines.Add(
        "Scope.Name=$(ConvertTo-ApprovalHashValue -Value $ScopeName)"
    )
    $lines.Add("Scope.PublicResearch=$(if ($PublicResearch) { 'true' } else { 'false' })")
    $lines.Add("Scope.ProvenanceResearch=$(if ($ProvenanceResearch) { 'true' } else { 'false' })")
    $lines.Add(
        "PriorArtWindow.Enabled=$(if ($PriorArtWindow.Enabled) { 'true' } else { 'false' })"
    )
    $lines.Add(
        "PriorArtWindow.LookbackMonths=$($PriorArtWindow.LookbackMonths)"
    )
    $lines.Add(
        "PriorArtWindow.StartDate=$(ConvertTo-ApprovalHashValue -Value ([string] $PriorArtWindow.StartDate))"
    )
    $lines.Add(
        "PriorArtWindow.EndDate=$(ConvertTo-ApprovalHashValue -Value ([string] $PriorArtWindow.EndDate))"
    )
    if ($null -ne $ProvenanceWindow) {
        $lines.Add('ProvenanceWindow=present')
        $lines.Add(
            "ProvenanceWindow.LookbackMonths=$($ProvenanceWindow.LookbackMonths)"
        )
        $lines.Add(
            "ProvenanceWindow.StartDate=$(ConvertTo-ApprovalHashValue -Value ([string] $ProvenanceWindow.StartDate))"
        )
        $lines.Add(
            "ProvenanceWindow.EndDate=$(ConvertTo-ApprovalHashValue -Value ([string] $ProvenanceWindow.EndDate))"
        )
    }
    else {
        $lines.Add('ProvenanceWindow=null')
    }
    $lines.Add("SessionTimeoutMinutes=$SessionTimeoutMinutes")
    $lines.Add("ThrottleLimit=$ThrottleLimit")
    $lines.Add("MaxRepositories=$MaxRepositories")
    $lines.Add("Model=$(ConvertTo-ApprovalHashValue -Value $Model)")
    $lines.Add(
        "OpenHtmlPolicy=$(ConvertTo-ApprovalHashValue -Value $OpenHtmlPolicy)"
    )

    return (($lines -join "`n") + "`n")
}

function Get-ApprovalHash {
    param(
        [Parameter(Mandatory)]
        [object[]] $Sources,

        [Parameter(Mandatory)]
        [string] $ReviewDate,

        [Parameter(Mandatory)]
        [string] $WorkspaceRoot,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [int] $ScopeNumber,

        [Parameter(Mandatory)]
        [string] $ScopeName,

        [Parameter(Mandatory)]
        [bool] $PublicResearch,

        [Parameter(Mandatory)]
        [bool] $ProvenanceResearch,

        [Parameter(Mandatory)]
        [psobject] $PriorArtWindow,

        [AllowNull()]
        [psobject] $ProvenanceWindow = $null,

        [Parameter(Mandatory)]
        [int] $SessionTimeoutMinutes,

        [Parameter(Mandatory)]
        [int] $ThrottleLimit,

        [Parameter(Mandatory)]
        [int] $MaxRepositories,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [string] $OpenHtmlPolicy
    )

    $material = ConvertTo-ApprovalHashMaterial @PSBoundParameters
    $utf8 = [Text.UTF8Encoding]::new($false)
    $hashBytes = [Security.Cryptography.SHA256]::HashData(
        $utf8.GetBytes($material)
    )
    return [Convert]::ToHexString($hashBytes).ToLowerInvariant()
}

function New-ReviewPlan {
    param(
        [Parameter(Mandatory)]
        [object[]] $Sources,

        [Parameter(Mandatory)]
        [string] $GeneratedAt,

        [Parameter(Mandatory)]
        [string] $ReviewDate,

        [Parameter(Mandatory)]
        [string] $WorkspaceRoot,

        [Parameter(Mandatory)]
        [string] $OutputRoot,

        [Parameter(Mandatory)]
        [int] $ScopeNumber,

        [Parameter(Mandatory)]
        [string] $ScopeName,

        [Parameter(Mandatory)]
        [string] $ScopeEstimate,

        [Parameter(Mandatory)]
        [bool] $PublicResearch,

        [Parameter(Mandatory)]
        [int] $PriorArtLookbackMonths,

        [Parameter(Mandatory)]
        [string] $PriorArtStartDate,

        [Parameter(Mandatory)]
        [bool] $ProvenanceResearch,

        [AllowNull()]
        [int] $ProvenanceLookbackMonths = $null,

        [AllowNull()]
        [string] $ProvenanceStartDate = $null,

        [Parameter(Mandatory)]
        [int] $SessionTimeoutMinutes,

        [Parameter(Mandatory)]
        [int] $ThrottleLimit,

        [Parameter(Mandatory)]
        [int] $MaxRepositories,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [string] $OpenHtmlPolicy,

        [AllowEmptyString()]
        [string] $ApprovalHash = '',

        [AllowEmptyString()]
        [string] $RunId = '',

        [AllowEmptyString()]
        [string] $StartedAt = ''
    )

    $sourcesList = [Collections.Generic.List[object]]::new()
    foreach ($source in $Sources) {
        $requestedCommit = [string] $source.RequestedCommit
        $localPath = [string] $source.SourcePath
        $sourcesList.Add([pscustomobject][ordered]@{
            Kind = $source.SourceKind
            LocalPath = if ([string]::IsNullOrWhiteSpace($localPath)) {
                $null
            }
            else {
                $localPath
            }
            RemoteUrl = $source.Url
            RequestedCommit = if ([string]::IsNullOrWhiteSpace($requestedCommit)) {
                $null
            }
            else {
                $requestedCommit
            }
            Slug = $source.Slug
        })
    }

    $provenanceWindow = if ($ProvenanceResearch) {
        [pscustomobject][ordered]@{
            LookbackMonths = $ProvenanceLookbackMonths
            StartDate = $ProvenanceStartDate
            EndDate = $ReviewDate
        }
    }
    else {
        $null
    }
    $priorArtWindow = [pscustomobject][ordered]@{
        Enabled = $PublicResearch
        LookbackMonths = $PriorArtLookbackMonths
        StartDate = $PriorArtStartDate
        EndDate = $ReviewDate
    }
    if ([string]::IsNullOrWhiteSpace($ApprovalHash)) {
        $ApprovalHash = Get-ApprovalHash `
            -Sources $sourcesList.ToArray() `
            -ReviewDate $ReviewDate `
            -WorkspaceRoot $WorkspaceRoot `
            -OutputRoot $OutputRoot `
            -ScopeNumber $ScopeNumber `
            -ScopeName $ScopeName `
            -PublicResearch $PublicResearch `
            -PriorArtWindow $priorArtWindow `
            -ProvenanceResearch $ProvenanceResearch `
            -ProvenanceWindow $provenanceWindow `
            -SessionTimeoutMinutes $SessionTimeoutMinutes `
            -ThrottleLimit $ThrottleLimit `
            -MaxRepositories $MaxRepositories `
            -Model $Model `
            -OpenHtmlPolicy $OpenHtmlPolicy
    }

    $plan = [ordered]@{
        SchemaVersion = $planSchemaVersion
        GeneratedAt = $GeneratedAt
        ReviewDate = $ReviewDate
        ApprovalHash = $ApprovalHash
    }
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $plan.RunId = $RunId
        $plan.StartedAt = $StartedAt
    }
    $plan.Sources = $sourcesList.ToArray()
    $plan.WorkspaceRoot = $WorkspaceRoot
    $plan.OutputRoot = $OutputRoot
    $plan.Scope = [pscustomobject][ordered]@{
        Number = $ScopeNumber
        Name = $ScopeName
        PlanningEstimate = $ScopeEstimate
        PublicResearch = $PublicResearch
        ProvenanceResearch = $ProvenanceResearch
    }
    $plan.PriorArtWindow = $priorArtWindow
    $plan.ProvenanceWindow = $provenanceWindow
    $plan.SessionTimeoutMinutes = $SessionTimeoutMinutes
    $plan.ThrottleLimit = $ThrottleLimit
    $plan.MaxRepositories = $MaxRepositories
    $plan.Model = $Model
    $plan.OpenHtmlPolicy = $OpenHtmlPolicy

    return [pscustomobject] $plan
}

function ConvertTo-ReviewPlanText {
    param(
        [Parameter(Mandatory)]
        [psobject] $Plan
    )

    $lines = [Collections.Generic.List[string]]::new()
    $rule = '=' * 80
    $addField = {
        param(
            [Parameter(Mandatory)]
            [string] $Label,

            [Parameter(Mandatory)]
            [string] $Value
        )

        $lines.Add(('{0,-20} {1}' -f $Label, $Value))
    }

    $lines.Add($rule)
    $lines.Add('EFFECTIVE REVIEW PLAN')
    $lines.Add($rule)
    & $addField 'Generated at (UTC):' $Plan.GeneratedAt
    & $addField 'Review date (local calendar):' $Plan.ReviewDate
    & $addField 'Approval hash:' $Plan.ApprovalHash
    if ($Plan.PSObject.Properties['RunId']) {
        & $addField 'Run ID:' ([string] $Plan.RunId)
        & $addField 'Started at:' ([string] $Plan.StartedAt)
    }
    & $addField 'Workspace root:' $Plan.WorkspaceRoot
    & $addField 'Output root:' $Plan.OutputRoot
    & $addField 'Scope:' $Plan.Scope.Name
    & $addField 'Planning estimate:' $Plan.Scope.PlanningEstimate
    & $addField 'Public research:' (Get-StatusWord -Enabled $Plan.Scope.PublicResearch)
    & $addField 'Provenance research:' (Get-StatusWord -Enabled $Plan.Scope.ProvenanceResearch)
    if ($Plan.PriorArtWindow.Enabled) {
        & $addField 'Prior-art lookback:' "$($Plan.PriorArtWindow.LookbackMonths) months"
        & $addField 'Prior-art window (local calendar):' "$($Plan.PriorArtWindow.StartDate) through $($Plan.PriorArtWindow.EndDate)"
    }
    else {
        & $addField 'Prior-art window (local calendar):' 'disabled'
    }
    if ($null -ne $Plan.ProvenanceWindow) {
        & $addField 'Provenance lookback:' "$($Plan.ProvenanceWindow.LookbackMonths) months"
        & $addField 'Provenance window (local calendar):' "$($Plan.ProvenanceWindow.StartDate) through $($Plan.ProvenanceWindow.EndDate)"
    }
    else {
        & $addField 'Provenance window (local calendar):' 'disabled'
    }
    & $addField 'Session timeout:' "$($Plan.SessionTimeoutMinutes) minutes"
    & $addField 'Throttle limit:' ([string] $Plan.ThrottleLimit)
    & $addField 'Maximum repositories:' ([string] $Plan.MaxRepositories)
    & $addField 'Model:' $Plan.Model
    & $addField 'Open HTML policy:' $Plan.OpenHtmlPolicy
    & $addField 'Sources:' ([string] @($Plan.Sources).Count)

    $sourceNumber = 1
    foreach ($source in @($Plan.Sources)) {
        $requestedCommit = if ([string]::IsNullOrWhiteSpace(
                [string] $source.RequestedCommit
            )) {
            '(none)'
        }
        else {
            [string] $source.RequestedCommit
        }
        $lines.Add("  [$sourceNumber] $($source.Slug)")
        $lines.Add(('      {0,-16} {1}' -f 'Kind:', $source.Kind))
        if (-not [string]::IsNullOrWhiteSpace([string] $source.LocalPath)) {
            $lines.Add(
                ('      {0,-16} {1}' -f 'Local path:', [string] $source.LocalPath)
            )
        }
        $lines.Add(('      {0,-16} {1}' -f 'Remote URL:', $source.RemoteUrl))
        $lines.Add(('      {0,-16} {1}' -f 'Requested commit:', $requestedCommit))
        $sourceNumber++
    }
    $lines.Add($rule)

    return (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

function ConvertTo-WholeNumberInRange {
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [int] $Minimum,

        [Parameter(Mandatory)]
        [int] $Maximum
    )

    $message = "$Name must be a whole number from $Minimum through $Maximum."
    if ($null -eq $Value) {
        throw $message
    }

    $text = switch ($Value) {
        { $_ -is [string] } {
            $_.Trim()
            break
        }
        { $_ -is [byte] -or $_ -is [sbyte] -or
            $_ -is [short] -or $_ -is [ushort] -or
            $_ -is [int] -or $_ -is [uint] -or
            $_ -is [long] -or $_ -is [ulong] } {
            [Convert]::ToString($_, [Globalization.CultureInfo]::InvariantCulture)
            break
        }
        default {
            throw $message
        }
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        throw $message
    }

    $parsed = 0
    if (-not [int]::TryParse(
            $text,
            [Globalization.NumberStyles]::None,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref] $parsed
        )) {
        throw $message
    }
    if ($parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw $message
    }

    return $parsed
}

function Resolve-CanonicalDirectoryPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $fullPath = [IO.Path]::GetFullPath(
        $ExecutionContext.SessionState.Path.
            GetUnresolvedProviderPathFromPSPath($Path)
    )
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Cannot resolve path root: $Path"
    }

    $relativePath = $fullPath.Substring($root.Length)
    $segments = @(
        $relativePath.Split(
            [char[]] @(
                [IO.Path]::DirectorySeparatorChar
                [IO.Path]::AltDirectorySeparatorChar
            ),
            [StringSplitOptions]::RemoveEmptyEntries
        )
    )
    $resolved = $root

    for ($index = 0; $index -lt $segments.Count; $index++) {
        $candidate = Join-Path $resolved $segments[$index]
        $item = Get-Item -LiteralPath $candidate -Force `
            -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            for ($remaining = $index; $remaining -lt $segments.Count; $remaining++) {
                $resolved = Join-Path $resolved $segments[$remaining]
            }
            return [IO.Path]::GetFullPath($resolved)
        }
        if (-not $item.PSIsContainer) {
            throw "Directory path resolves through a file: $Path"
        }

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $target = $item.ResolveLinkTarget($true)
            if ($null -eq $target) {
                throw "Directory path contains a dangling link: $Path"
            }
            $target.Refresh()
            if (-not $target.Exists -or
                $target -isnot [IO.DirectoryInfo]) {
                throw "Directory link target is not an existing directory: $Path"
            }
            $resolved = $target.FullName
        }
        else {
            $resolved = $item.FullName
        }
    }

    return [IO.Path]::GetFullPath($resolved)
}

function Test-PathContains {
    param(
        [Parameter(Mandatory)]
        [string] $Parent,

        [Parameter(Mandatory)]
        [string] $Child
    )

    $comparison = if ($IsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }
    $separator = [IO.Path]::DirectorySeparatorChar
    $normalizedParent = [IO.Path]::TrimEndingDirectorySeparator($Parent)
    $normalizedChild = [IO.Path]::TrimEndingDirectorySeparator($Child)
    $parentPrefix = if ($normalizedParent.EndsWith($separator)) {
        $normalizedParent
    }
    else {
        "$normalizedParent$separator"
    }

    return $normalizedChild.Equals($normalizedParent, $comparison) -or
        $normalizedChild.StartsWith(
            $parentPrefix,
            $comparison
        )
}

function Get-NearestExistingDirectoryPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $cursor = $Path
    while (-not (Test-Path -LiteralPath $cursor)) {
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) {
            throw "Cannot find an existing ancestor for path: $Path"
        }
        $cursor = $parent
    }
    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        throw "Path ancestor is not a directory: $cursor"
    }

    return $cursor
}

function Assert-PathOutsideGitRepository {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Label,

        [Parameter(Mandatory)]
        [string] $GitPath
    )

    $ancestor = Get-NearestExistingDirectoryPath -Path $Path
    $probe = @(
        & $GitPath -C $ancestor rev-parse --git-dir 2>&1
    )
    $probeExitCode = $LASTEXITCODE
    if ($probeExitCode -eq 0) {
        throw "$Label must not be inside a Git worktree or Git metadata directory."
    }
    $probeText = $probe -join "`n"
    if ($probeExitCode -ne 128 -or
        $probeText -notmatch '(?i)not a git repository') {
        throw "Could not verify Git isolation for $Label at ${ancestor}: $probeText"
    }
}

function New-RepositorySlug {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryHost,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $hostPart = if ($RepositoryHost.Equals(
        'github.com',
        [StringComparison]::OrdinalIgnoreCase
    )) {
        'github'
    }
    else {
        $RepositoryHost -replace '[^A-Za-z0-9]+', '-'
    }
    $pathPart = $Path.Trim('/') -replace '\.git$', ''
    $pathPart = $pathPart -replace '[^A-Za-z0-9._-]+', '--'
    $slug = "$hostPart--$pathPart".Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug) -or $slug.Length -gt 120) {
        throw 'Repository host and path are too long for safe artifact naming.'
    }

    return $slug
}

function Test-PublicIpAddress {
    param(
        [Parameter(Mandatory)]
        [Net.IPAddress] $Address
    )

    if ($Address.IsIPv4MappedToIPv6) {
        return Test-PublicIpAddress -Address $Address.MapToIPv4()
    }
    if ([Net.IPAddress]::IsLoopback($Address)) {
        return $false
    }

    $bytes = $Address.GetAddressBytes()
    if ($Address.AddressFamily -eq
        [Net.Sockets.AddressFamily]::InterNetwork) {
        if ($bytes[0] -eq 0 -or
            $bytes[0] -eq 10 -or
            $bytes[0] -eq 127 -or
            $bytes[0] -ge 224 -or
            ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and
                $bytes[1] -le 127) -or
            ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
            ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and
                $bytes[1] -le 31) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and
                $bytes[2] -eq 0) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and
                $bytes[2] -eq 2) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
            ($bytes[0] -eq 198 -and $bytes[1] -ge 18 -and
                $bytes[1] -le 19) -or
            ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and
                $bytes[2] -eq 100) -or
            ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and
                $bytes[2] -eq 113)) {
            return $false
        }
        return $true
    }

    if ($Address.AddressFamily -ne
        [Net.Sockets.AddressFamily]::InterNetworkV6) {
        return $false
    }
    if (($bytes[0] -band 0xE0) -ne 0x20 -or
        ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8) -or
        ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and
            $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) -or
        ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x02) -or
        ($bytes[0] -eq 0x3F -and ($bytes[1] -band 0xF0) -eq 0xF0)) {
        return $false
    }

    return $true
}

function Resolve-PublicRepositoryEndpoint {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryHost,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $Port
    )

    try {
        $lookup = [Net.Dns]::GetHostAddressesAsync($RepositoryHost)
        if (-not $lookup.Wait(5000)) {
            throw 'DNS lookup timed out.'
        }
        $addresses = @(
            $lookup.GetAwaiter().GetResult() |
                Sort-Object { $_.ToString() } -Unique
        )
    }
    catch {
        throw (
            "Could not resolve public repository host ${RepositoryHost}: " +
            $_.Exception.Message
        )
    }
    if ($addresses.Count -eq 0) {
        throw "Public repository host did not resolve: $RepositoryHost"
    }
    $nonPublic = @(
        $addresses | Where-Object {
            -not (Test-PublicIpAddress -Address $_)
        }
    )
    if ($nonPublic.Count -gt 0) {
        throw (
            'Repository host must resolve only to public IP addresses: ' +
            $RepositoryHost
        )
    }
    $formatted = @(
        $addresses | ForEach-Object {
            if ($_.AddressFamily -eq
                [Net.Sockets.AddressFamily]::InterNetworkV6) {
                "[$($_.ToString())]"
            }
            else {
                $_.ToString()
            }
        }
    )

    return "${RepositoryHost}:${Port}:$($formatted -join ',')"
}

function ConvertTo-PublicHttpsRepository {
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    $value = $Url.Trim().TrimEnd('/')
    if ($value -match '[\x00-\x20\x7F]' -or
        $value -match '%(?![0-9a-fA-F]{2})' -or
        $value -match '(?i)%0[0-9a-f]|%1[0-9a-f]|%7f|%2f|%5c') {
        throw "Repository URL contains unsupported characters: $Url"
    }
    try {
        $uri = [Uri] $value
    }
    catch {
        throw "Invalid repository URL: $Url"
    }

    if (-not $uri.IsAbsoluteUri -or
        -not $uri.Scheme.Equals(
            'https',
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw (
            'Only anonymous public HTTPS Git repository URLs without embedded ' +
            "credentials, queries, or fragments are supported: $Url"
        )
    }

    $repositoryHost = $uri.IdnHost.ToLowerInvariant()
    $address = $null
    $reservedSuffixes = @(
        '.localhost'
        '.local'
        '.localdomain'
        '.internal'
        '.home'
        '.lan'
        '.corp'
        '.test'
        '.invalid'
        '.example'
    )
    if ([Net.IPAddress]::TryParse($repositoryHost, [ref] $address) -or
        -not $repositoryHost.Contains('.') -or
        $repositoryHost -eq 'localhost' -or
        @(
            $reservedSuffixes | Where-Object {
                $repositoryHost.EndsWith(
                    $_,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
        ).Count -gt 0) {
        throw "Repository host must be a public DNS name: $Url"
    }
    foreach ($label in $repositoryHost.Split('.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
            throw "Repository host contains an unsupported DNS label: $Url"
        }
    }

    $escapedPath = $uri.AbsolutePath.TrimEnd('/')
    $decodedPath = [Uri]::UnescapeDataString($escapedPath)
    if ([string]::IsNullOrWhiteSpace($decodedPath.Trim('/')) -or
        $decodedPath -match '[\x00-\x20\x7F\\]') {
        throw "Repository URL must contain a safe non-empty Git path: $Url"
    }
    $escapedPath = $escapedPath -replace '(?i)\.git$', ''
    $authority = $repositoryHost
    if (-not $uri.IsDefaultPort) {
        $authority = "${authority}:$($uri.Port)"
    }
    $canonicalUrl = "https://$authority$escapedPath"

    $result = [pscustomobject]@{
        Url = $canonicalUrl
        Slug = New-RepositorySlug `
            -RepositoryHost $repositoryHost `
            -Path $decodedPath
        SourceKind = 'RemoteUrl'
        SourcePath = ''
        RequestedCommit = ''
        RepositoryHost = $repositoryHost
        RepositoryPort = if ($uri.IsDefaultPort) { 443 } else { $uri.Port }
        CurlResolve = ''
    }
    return $result
}

function Invoke-LocalGit {
    param(
        [Parameter(Mandatory)]
        [string] $GitPath,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $GitPath
    $process.StartInfo.WorkingDirectory = $WorkingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }
    foreach ($name in @($process.StartInfo.Environment.Keys)) {
        if ($name -like 'GIT_*') {
            [void] $process.StartInfo.Environment.Remove($name)
        }
    }
    $process.StartInfo.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $process.StartInfo.Environment['GIT_CONFIG_GLOBAL'] = if ($IsWindows) {
        'NUL'
    }
    else {
        '/dev/null'
    }
    $process.StartInfo.Environment['GIT_ATTR_NOSYSTEM'] = '1'
    $process.StartInfo.Environment['GIT_DISCOVERY_ACROSS_FILESYSTEM'] = '1'
    $process.StartInfo.Environment['GIT_LFS_SKIP_SMUDGE'] = '1'
    $process.StartInfo.Environment['GIT_NO_REPLACE_OBJECTS'] = '1'
    $process.StartInfo.Environment['GIT_OPTIONAL_LOCKS'] = '0'
    $process.StartInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'

    try {
        if (-not $process.Start()) {
            throw 'Git process did not start.'
        }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Git metadata lookup timed out.'
        }
        $output = $outputTask.GetAwaiter().GetResult().Trim()
        $error = $errorTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw $error
        }
        return $output
    }
    finally {
        $process.Dispose()
    }
}

function Get-AnonymousGitRepositoryArguments {
    param(
        [Parameter(Mandatory)]
        [string] $NullDevice,

        [Parameter(Mandatory)]
        [string] $CurlResolve,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    return @(
        '-c'
        "core.hooksPath=$NullDevice"
        '-c'
        'protocol.allow=never'
        '-c'
        'protocol.https.allow=always'
        '-c'
        'protocol.file.allow=never'
        '-c'
        'protocol.ext.allow=never'
        '-c'
        'credential.helper='
        '-c'
        'credential.interactive=false'
        '-c'
        'http.extraHeader='
        '-c'
        'http.proxy='
        '-c'
        'http.sslVerify=true'
        '-c'
        'http.followRedirects=false'
        '-c'
        "http.curloptResolve=$CurlResolve"
    ) + $Arguments
}

function Invoke-AnonymousGitCommand {
    param(
        [Parameter(Mandatory)]
        [string] $GitPath,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string] $AnonymousGitHome,

        [Parameter(Mandatory)]
        [string] $NullDevice,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $gitProcess = [Diagnostics.Process]::new()
    $gitProcess.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $gitProcess.StartInfo.FileName = $GitPath
    $gitProcess.StartInfo.WorkingDirectory = $WorkingDirectory
    $gitProcess.StartInfo.UseShellExecute = $false
    $gitProcess.StartInfo.CreateNoWindow = $true
    $gitProcess.StartInfo.RedirectStandardOutput = $true
    $gitProcess.StartInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void] $gitProcess.StartInfo.ArgumentList.Add($argument)
    }
    foreach ($name in @($gitProcess.StartInfo.Environment.Keys)) {
        if ($name -like 'GIT_*' -or
            $name -like 'GCM_*' -or
            $name -in @(
                'COPILOT_GITHUB_TOKEN'
                'GH_TOKEN'
                'GITHUB_TOKEN'
                'SSH_ASKPASS'
                'SSH_AUTH_SOCK'
                'NETRC'
                'HTTP_PROXY'
                'HTTPS_PROXY'
                'ALL_PROXY'
                'NO_PROXY'
            )) {
            [void] $gitProcess.StartInfo.Environment.Remove($name)
        }
    }
    $gitProcess.StartInfo.Environment['HOME'] = $AnonymousGitHome
    $gitProcess.StartInfo.Environment['USERPROFILE'] = $AnonymousGitHome
    $gitProcess.StartInfo.Environment['XDG_CONFIG_HOME'] = $AnonymousGitHome
    $gitProcess.StartInfo.Environment['CURL_HOME'] = $AnonymousGitHome
    $gitProcess.StartInfo.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $gitProcess.StartInfo.Environment['GIT_CONFIG_GLOBAL'] = $NullDevice
    $gitProcess.StartInfo.Environment['GIT_ATTR_NOSYSTEM'] = '1'
    $gitProcess.StartInfo.Environment['GIT_DISCOVERY_ACROSS_FILESYSTEM'] = '1'
    $gitProcess.StartInfo.Environment['GIT_LFS_SKIP_SMUDGE'] = '1'
    $gitProcess.StartInfo.Environment['GIT_NO_REPLACE_OBJECTS'] = '1'
    $gitProcess.StartInfo.Environment['GIT_OPTIONAL_LOCKS'] = '0'
    $gitProcess.StartInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'

    try {
        if (-not $gitProcess.Start()) {
            throw 'Git process did not start.'
        }
        $stdoutTask = $gitProcess.StandardOutput.ReadToEndAsync()
        $stderrTask = $gitProcess.StandardError.ReadToEndAsync()
        $gitProcess.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult().TrimEnd()
        $stderr = $stderrTask.GetAwaiter().GetResult().TrimEnd()
        $combined = @(
            $stdout
            $stderr
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return [pscustomobject]@{
            ExitCode = $gitProcess.ExitCode
            Output = $combined -join "`n"
        }
    }
    finally {
        $gitProcess.Dispose()
    }
}

function Test-RepositoryAccessibilityPreflight {
    param(
        [Parameter(Mandatory)]
        [object] $Job,

        [Parameter(Mandatory)]
        [string] $GitPath,

        [Parameter(Mandatory)]
        [string] $RunWorkspace,

        [Parameter(Mandatory)]
        [string] $AnonymousGitHome,

        [Parameter(Mandatory)]
        [string] $NullDevice
    )

    $notApplicable = 'NOT APPLICABLE'
    $lsRemoteResult = Invoke-AnonymousGitCommand `
        -GitPath $GitPath `
        -WorkingDirectory $RunWorkspace `
        -AnonymousGitHome $AnonymousGitHome `
        -NullDevice $NullDevice `
        -Arguments (
            Get-AnonymousGitRepositoryArguments `
                -NullDevice $NullDevice `
                -CurlResolve $Job.CurlResolve `
                -Arguments @(
                    'ls-remote'
                    '--symref'
                    '--exit-code'
                    '--'
                    $Job.Url
                    'HEAD'
                )
    )
    if ($lsRemoteResult.ExitCode -ne 0) {
        return [pscustomobject]@{
            Passed = $false
            ExitCode = $lsRemoteResult.ExitCode
            FailureSummary = (
                'Anonymous repository accessibility preflight failed. ' +
                'Rhyolite currently supports only publicly accessible ' +
                'repositories and does not attempt authentication. See ' +
                'errors.txt.'
            )
            ErrorText = @"
Anonymous repository accessibility preflight failed.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Repository: $($Job.Url)
Source kind: $($Job.SourceKind)
Selected source path: $(if ([string]::IsNullOrWhiteSpace($Job.SourcePath)) { $notApplicable } else { $Job.SourcePath })
Requested commit: $(if ([string]::IsNullOrWhiteSpace($Job.RequestedCommit)) { 'HEAD' } else { $Job.RequestedCommit })
Git command: git ls-remote --symref --exit-code -- $($Job.Url) HEAD
Exit code: $($lsRemoteResult.ExitCode)

$($lsRemoteResult.Output)
"@.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($Job.RequestedCommit)) {
        return [pscustomobject]@{
            Passed = $true
            ExitCode = 0
            FailureSummary = ''
            ErrorText = ''
        }
    }

    $preflightPath = Join-Path $RunWorkspace "$($Job.Slug)-preflight"
    Remove-Item -LiteralPath $preflightPath -Recurse -Force `
        -ErrorAction SilentlyContinue
    try {
        $initResult = Invoke-AnonymousGitCommand `
            -GitPath $GitPath `
            -WorkingDirectory $RunWorkspace `
            -AnonymousGitHome $AnonymousGitHome `
            -NullDevice $NullDevice `
            -Arguments @(
                'init'
                '--quiet'
                '--'
                $preflightPath
            )
        if ($initResult.ExitCode -ne 0) {
            return [pscustomobject]@{
                Passed = $false
                ExitCode = $initResult.ExitCode
                FailureSummary = (
                    'Anonymous repository accessibility preflight could not ' +
                    'initialize exact-commit verification. See errors.txt.'
                )
                ErrorText = @"
Anonymous repository accessibility preflight could not initialize exact-commit verification.
Repository: $($Job.Url)
Source kind: $($Job.SourceKind)
Selected source path: $(if ([string]::IsNullOrWhiteSpace($Job.SourcePath)) { $notApplicable } else { $Job.SourcePath })
Requested commit: $($Job.RequestedCommit)
Git command: git init --quiet -- $preflightPath
Exit code: $($initResult.ExitCode)

$($initResult.Output)
"@.Trim()
            }
        }

        $fetchResult = Invoke-AnonymousGitCommand `
            -GitPath $GitPath `
            -WorkingDirectory $preflightPath `
            -AnonymousGitHome $AnonymousGitHome `
            -NullDevice $NullDevice `
            -Arguments (
                Get-AnonymousGitRepositoryArguments `
                    -NullDevice $NullDevice `
                    -CurlResolve $Job.CurlResolve `
                    -Arguments @(
                        'fetch'
                        '--quiet'
                        '--no-tags'
                        '--depth=1'
                        '--'
                        $Job.Url
                        $Job.RequestedCommit
                    )
        )
        if ($fetchResult.ExitCode -ne 0) {
            return [pscustomobject]@{
                Passed = $false
                ExitCode = $fetchResult.ExitCode
                FailureSummary = (
                    'Anonymous repository accessibility preflight could not ' +
                    'verify the exact commit. Rhyolite currently supports only ' +
                    'publicly accessible repositories and does not attempt ' +
                    'authentication. See errors.txt.'
                )
                ErrorText = @"
Anonymous repository accessibility preflight could not verify the exact commit.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Repository: $($Job.Url)
Source kind: $($Job.SourceKind)
Selected source path: $(if ([string]::IsNullOrWhiteSpace($Job.SourcePath)) { $notApplicable } else { $Job.SourcePath })
Requested commit: $($Job.RequestedCommit)
Git command: git fetch --quiet --no-tags --depth=1 -- $($Job.Url) $($Job.RequestedCommit)
Exit code: $($fetchResult.ExitCode)

$($fetchResult.Output)
"@.Trim()
            }
        }

        $verifyOutput = @(
            & $GitPath -C $preflightPath rev-parse --verify 'FETCH_HEAD^{commit}' 2>&1
        ) -join "`n"
        $verifyExitCode = $LASTEXITCODE
        if ($verifyExitCode -ne 0) {
            return [pscustomobject]@{
                Passed = $false
                ExitCode = $verifyExitCode
                FailureSummary = (
                    'Anonymous repository accessibility preflight could not ' +
                    'verify the exact fetched commit. See errors.txt.'
                )
                ErrorText = @"
Anonymous repository accessibility preflight could not verify the exact fetched commit.
Repository: $($Job.Url)
Source kind: $($Job.SourceKind)
Selected source path: $(if ([string]::IsNullOrWhiteSpace($Job.SourcePath)) { $notApplicable } else { $Job.SourcePath })
Requested commit: $($Job.RequestedCommit)
Git command: git rev-parse --verify FETCH_HEAD^{commit}
Exit code: $verifyExitCode

$verifyOutput
"@.Trim()
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $preflightPath -Recurse -Force `
            -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Passed = $true
        ExitCode = 0
        FailureSummary = ''
        ErrorText = ''
    }
}

function New-RepositoryResultSkeleton {
    param(
        [Parameter(Mandatory)]
        [object] $Job,

        [Parameter(Mandatory)]
        [string] $RunResults,

        [Parameter(Mandatory)]
        [string] $ScopeName,

        [Parameter(Mandatory)]
        [string] $ScopeEstimate,

        [Parameter(Mandatory)]
        [bool] $PublicResearch,

        [Parameter(Mandatory)]
        [bool] $ProvenanceResearch,

        [Parameter(Mandatory)]
        [string] $Status,

        [Parameter(Mandatory)]
        [int] $ExitCode,

        [Parameter(Mandatory)]
        [string] $StartedAt,

        [AllowEmptyString()]
        [string] $Checkout = '',

        [AllowEmptyString()]
        [string] $VerificationClone = ''
    )

    $repositoryResultPath = Join-Path $RunResults $Job.Slug
    New-Item -ItemType Directory -Path $repositoryResultPath -Force | Out-Null

    return [pscustomobject]@{
        Slug = $Job.Slug
        Repository = $Job.Url
        SourceKind = $Job.SourceKind
        SourcePath = $Job.SourcePath
        RequestedCommit = $Job.RequestedCommit
        SessionId = $null
        Session = $null
        Commit = $null
        Status = $Status
        ExitCode = $ExitCode
        StartedAt = $StartedAt
        CompletedAt = [DateTime]::UtcNow.ToString('o')
        Scope = $ScopeName
        ScopeEstimate = $ScopeEstimate
        PublicResearch = $PublicResearch
        ProvenanceResearch = $ProvenanceResearch
        Checkout = $Checkout
        VerificationClone = $VerificationClone
        OutputDirectory = $repositoryResultPath
        PlainText = Join-Path $repositoryResultPath 'review.txt'
        Markdown = Join-Path $repositoryResultPath 'review.md'
        Html = Join-Path $repositoryResultPath 'review.html'
        Timeline = Join-Path $repositoryResultPath 'analysis-timeline.txt'
        Transcript = Join-Path $repositoryResultPath 'session.md'
        Request = Join-Path $repositoryResultPath 'request.txt'
        Errors = Join-Path $repositoryResultPath 'errors.txt'
        State = Join-Path $repositoryResultPath 'state.json'
        Handoff = Join-Path $repositoryResultPath 'handoff.md'
    }
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Split-Path -Parent (Split-Path -Parent $skillRoot)
Set-RhyoliteRepositorySupportLinks -PluginRoot $pluginRoot
$promptPath = Join-Path $skillRoot 'review-prompt.txt'
$outputModulePath = Join-Path $PSScriptRoot 'ReviewOutput.psm1'

if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
    throw "Prompt template not found: $promptPath"
}
if (-not (Test-Path -LiteralPath $outputModulePath -PathType Leaf)) {
    throw "Output processing module not found: $outputModulePath"
}

$requiredPlaceholders = @(
    '{{REPOSITORY_URL}}'
    '{{REPOSITORY_PATH}}'
    '{{COMMIT}}'
    '{{REVIEW_DATE}}'
    '{{PRIOR_ART_START_DATE}}'
    '{{PROVENANCE_LOOKBACK_MONTHS}}'
    '{{PROVENANCE_START_DATE}}'
    '{{SCOPE_NAME}}'
    '{{OUTPUT_DIRECTORY}}'
    '{{REPOSITORY_METADATA}}'
    '{{PUBLIC_RESEARCH_INSTRUCTIONS}}'
    '{{PROVENANCE_INSTRUCTIONS}}'
)
$promptTemplate = Get-Content -LiteralPath $promptPath -Raw
foreach ($placeholder in $requiredPlaceholders) {
    if (-not $promptTemplate.Contains($placeholder)) {
        throw "Prompt template is missing required placeholder: $placeholder"
    }
}

if ($PSCmdlet.ParameterSetName -eq 'File') {
    foreach ($line in Get-Content -LiteralPath $RepositoryListPath) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) {
            continue
        }
        if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
            $Repository += $value
        }
        else {
            throw (
                "Repository list contains an unsupported local path or non-URL " +
                "entry: $value`nSupply only anonymously readable public HTTPS " +
                'Git repository URLs.'
            )
        }
    }
}

$sourceCount = @($Repository).Count
if (@($RepositoryPath).Count -gt 0) {
    throw (
        'Local repository paths are not supported. Supply only anonymously ' +
        'readable public HTTPS Git repository URLs.'
    )
}
if ($sourceCount -eq 0) {
    throw 'No repository URLs were provided.'
}

if ($sourceCount -gt $MaxRepositories) {
    throw "Received $sourceCount repositories; maximum is $MaxRepositories."
}
if ($Commit -and
    (@($Repository).Count -ne 1)) {
    throw '-Commit can be used only with one remote repository URL.'
}

$jobs = [Collections.Generic.List[object]]::new()
foreach ($repositoryUrl in @($Repository)) {
    $job = ConvertTo-PublicHttpsRepository -Url $repositoryUrl
    $job.RequestedCommit = $Commit
    $jobs.Add($job)
}

$duplicateSlugs = @($jobs | Group-Object Slug | Where-Object Count -gt 1)
if ($duplicateSlugs.Count -gt 0) {
    throw "Duplicate repositories were provided: $($duplicateSlugs.Name -join ', ')"
}

if ($OpenHtml -and $NoOpenHtml) {
    throw '-OpenHtml and -NoOpenHtml cannot be used together.'
}
if ($ValidateOnly -and $PlanOnly) {
    throw '-ValidateOnly and -PlanOnly cannot be used together.'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPlanHash)) {
    if ($ExpectedPlanHash -notmatch '^[0-9a-fA-F]{64}$') {
        throw '-ExpectedPlanHash must be a 64-character hexadecimal SHA-256 value.'
    }
    $ExpectedPlanHash = $ExpectedPlanHash.ToLowerInvariant()
}

$canPromptForSetup = -not $ValidateOnly -and
    -not $PlanOnly -and
    (Test-InteractiveConsole)

$scopeWasSpecified = $PSBoundParameters.ContainsKey('Scope')
if ($scopeWasSpecified) {
    $Scope = ConvertTo-WholeNumberInRange `
        -Value $Scope `
        -Name '-Scope' `
        -Minimum 1 `
        -Maximum 3
}
else {
    $Scope = 0
}
if ($scopeWasSpecified -and
    ($EnablePublicResearch -or $EnableProvenanceResearch)) {
    throw 'Use either -Scope or the legacy research switches, not both.'
}

if (-not $scopeWasSpecified) {
    if ($EnableProvenanceResearch -and -not $EnablePublicResearch) {
        throw 'Provenance research requires -EnablePublicResearch.'
    }
    if ($EnableProvenanceResearch) {
        $Scope = 3
    }
    elseif ($EnablePublicResearch) {
        $Scope = 2
    }
    elseif ($canPromptForSetup) {
        Write-Host 'Select review scope:'
        Write-Host (
            '  1. Core review (recommended for a first run): source, history, ' +
            'architecture, quality, and a security specialist. Roughly ' +
            '15-45 minutes per repository; lowest AI-credit and network use.'
        )
        Write-Host (
            '  2. Core + public prior-art/community research: adds a research ' +
            'specialist and public web requests. Roughly 30-90+ minutes per ' +
            'repository and materially higher AI-credit/network use.'
        )
        Write-Host (
            '  3. Full + whole-repository exact-commit evidence-based ' +
            'provenance of agentically generated code: broadest scope, ' +
            'roughly 60-120+ minutes per repository, highest resource use, ' +
            'and mandatory human review before sharing.'
        )
        Write-Host (
            'Estimates are planning ranges and can increase substantially for ' +
            'large repositories or broad research topics.'
        )
        $scopeInput = (Read-Host 'Scope [1]').Trim()
        if ([string]::IsNullOrWhiteSpace($scopeInput)) {
            $Scope = 1
        }
        elseif ($scopeInput -match '^[123]$') {
            $Scope = [int] $scopeInput
        }
        else {
            throw 'Scope must be 1, 2, or 3.'
        }
    }
    else {
        $Scope = 1
    }
}

$scopeDetails = switch ($Scope) {
    1 {
        [pscustomobject]@{
            Name = '1 - Core repository review'
            Estimate = 'Roughly 15-45 minutes per repository; lowest resource use.'
            PublicResearch = $false
            ProvenanceResearch = $false
        }
    }
    2 {
        [pscustomobject]@{
            Name = '2 - Core plus public prior-art and community research'
            Estimate = 'Roughly 30-90+ minutes per repository; additional research agent, public network requests, and AI credits.'
            PublicResearch = $true
            ProvenanceResearch = $false
        }
    }
    3 {
        [pscustomobject]@{
            Name = '3 - Full review plus whole-repository exact-commit evidence-based provenance of agentically generated code'
            Estimate = 'Roughly 60-120+ minutes per repository; highest model, subagent, and network use; human review required.'
            PublicResearch = $true
            ProvenanceResearch = $true
        }
    }
    default {
        throw 'Scope must be 1, 2, or 3.'
    }
}

$publicResearchEnabled = $scopeDetails.PublicResearch
$provenanceResearchEnabled = $scopeDetails.ProvenanceResearch
$provenanceLookbackWasSpecified = $PSBoundParameters.ContainsKey(
    'ProvenanceLookbackMonths'
)
if ($provenanceLookbackWasSpecified) {
    $ProvenanceLookbackMonths = ConvertTo-WholeNumberInRange `
        -Value $ProvenanceLookbackMonths `
        -Name '-ProvenanceLookbackMonths' `
        -Minimum 1 `
        -Maximum 60
}
else {
    $ProvenanceLookbackMonths = $null
}
if (-not $provenanceResearchEnabled -and
    $provenanceLookbackWasSpecified) {
    throw '-ProvenanceLookbackMonths can be used only with Scope 3 provenance research.'
}
if ($provenanceResearchEnabled -and $null -eq $ProvenanceLookbackMonths) {
    if ($canPromptForSetup) {
        $provenanceInput = (
            Read-Host "Provenance lookback months [$defaultProvenanceLookbackMonths]"
        ).Trim()
        if ([string]::IsNullOrWhiteSpace($provenanceInput)) {
            $ProvenanceLookbackMonths = $defaultProvenanceLookbackMonths
        }
        else {
            $ProvenanceLookbackMonths = ConvertTo-WholeNumberInRange `
                -Value $provenanceInput `
                -Name 'Provenance lookback months' `
                -Minimum 1 `
                -Maximum 60
        }
    }
    else {
        $ProvenanceLookbackMonths = $defaultProvenanceLookbackMonths
    }
}
elseif (-not $provenanceResearchEnabled) {
    $ProvenanceLookbackMonths = $null
}
if ($SessionTimeoutMinutes -eq 0) {
    $SessionTimeoutMinutes = switch ($Scope) {
        1 { 60 }
        2 { 120 }
        3 { 240 }
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Get-DefaultOutputRoot
}
$defaultOutputRoot = $OutputRoot
if ($canPromptForSetup -and
    -not $PSBoundParameters.ContainsKey('OutputRoot')) {
    Write-Host ''
    Write-Host (
        'Review artifacts require a writable directory that is separate from ' +
        'the read-only checkout.'
    )
    $outputInput = (
        Read-Host "Output root [$defaultOutputRoot]"
    ).Trim()
    if (-not [string]::IsNullOrWhiteSpace($outputInput)) {
        $OutputRoot = $outputInput
    }
}
foreach ($candidatePath in @($WorkspaceRoot, $OutputRoot)) {
    if ($candidatePath -match '[\x00-\x1F\x7F]') {
        throw 'Workspace and output paths must not contain control characters.'
    }
}

$canonicalWorkspaceRoot = Resolve-CanonicalDirectoryPath -Path $WorkspaceRoot
$canonicalOutputRoot = Resolve-CanonicalDirectoryPath -Path $OutputRoot
if ((Test-PathContains -Parent $canonicalWorkspaceRoot -Child $canonicalOutputRoot) -or
    (Test-PathContains -Parent $canonicalOutputRoot -Child $canonicalWorkspaceRoot)) {
    throw (
        'The writable output root and read-only checkout workspace must be ' +
        "disjoint. Workspace: $canonicalWorkspaceRoot; output: " +
        $canonicalOutputRoot
    )
}
$WorkspaceRoot = $canonicalWorkspaceRoot
$OutputRoot = $canonicalOutputRoot

$publicResearchInstructions = if ($publicResearchEnabled) {
    @'
ENABLED. Invoke a separate research specialist. Search only public sources.
Do not include private code, internal names, internal URLs, credentials, or
non-public information in search queries.
'@
}
else {
    @'
DISABLED. Do not perform public web research or invoke the research specialist.
State that prior-art and community research were not requested.
'@
}

$provenanceInstructions = if ($provenanceResearchEnabled) {
    @'
ENABLED. Assess whole-repository, exact-commit, evidence-based provenance of
agentically generated code within the stated provenance window. Style, commit
size, quality, or similarity alone cannot prove AI generation, copying,
plagiarism, intent, or misconduct. Require public evidence, chronology,
source lineage, alternative explanations, confidence, and human review.
'@
}
else {
    @'
DISABLED. Do not analyze whether the repository contains agentically
generated code or make unsupported claims about copying, plagiarism,
intent, or misconduct.
'@
}

$reviewTimestamp = Get-Date
$planGeneratedAt = Get-UtcTimestamp
$reviewDate = $reviewTimestamp.ToString('yyyy-MM-dd')
$priorArtStartDate = $reviewTimestamp.
    AddMonths(-$defaultPriorArtLookbackMonths).
    ToString('yyyy-MM-dd')
$provenanceStartDate = if ($provenanceResearchEnabled) {
    $reviewTimestamp.
        AddMonths(-$ProvenanceLookbackMonths).
        ToString('yyyy-MM-dd')
}
else {
    $null
}
$provenanceWindowState = if ($provenanceResearchEnabled) {
    [ordered]@{
        LookbackMonths = $ProvenanceLookbackMonths
        StartDate = $provenanceStartDate
        EndDate = $reviewDate
    }
}
else {
    $null
}
$provenanceWindowText = if ($provenanceResearchEnabled) {
    @"
Lookback months: $ProvenanceLookbackMonths
Start date: $provenanceStartDate
End date: $reviewDate
"@.Trim()
}
else {
    'Disabled'
}
$provenanceLookbackPromptValue = if ($provenanceResearchEnabled) {
    [string] $ProvenanceLookbackMonths
}
else {
    'disabled'
}
$provenanceStartDatePromptValue = if ($provenanceResearchEnabled) {
    $provenanceStartDate
}
else {
    'disabled'
}
$scopeName = $scopeDetails.Name
$scopeEstimate = $scopeDetails.Estimate
$openHtmlPolicy = Get-ReviewPlanOpenHtmlPolicy
$nullDevice = if ($IsWindows) { 'NUL' } else { '/dev/null' }
$gitPath = $null
if ($PlanOnly -or -not $ValidateOnly) {
    $gitPath = Resolve-ApplicationPath -Name 'git'
    Clear-InheritedGitEnvironment
    Assert-PathOutsideGitRepository `
        -Path $WorkspaceRoot `
        -Label 'The checkout workspace root' `
        -GitPath $gitPath
    Assert-PathOutsideGitRepository `
        -Path $OutputRoot `
        -Label 'The artifact output root' `
        -GitPath $gitPath
}
$effectivePlan = New-ReviewPlan `
    -Sources $jobs.ToArray() `
    -GeneratedAt $planGeneratedAt `
    -ReviewDate $reviewDate `
    -WorkspaceRoot $WorkspaceRoot `
    -OutputRoot $OutputRoot `
    -ScopeNumber $Scope `
    -ScopeName $scopeName `
    -ScopeEstimate $scopeEstimate `
    -PublicResearch $publicResearchEnabled `
    -PriorArtLookbackMonths $defaultPriorArtLookbackMonths `
    -PriorArtStartDate $priorArtStartDate `
    -ProvenanceResearch $provenanceResearchEnabled `
    -ProvenanceLookbackMonths $ProvenanceLookbackMonths `
    -ProvenanceStartDate $provenanceStartDate `
    -SessionTimeoutMinutes $SessionTimeoutMinutes `
    -ThrottleLimit $ThrottleLimit `
    -MaxRepositories $MaxRepositories `
    -Model $Model `
    -OpenHtmlPolicy $openHtmlPolicy

if ($ValidateOnly) {
    $jobs | Select-Object SourceKind, SourcePath, Url, RequestedCommit, Slug
    Write-Host ''
    Write-Host "Prompt template:       $promptPath"
    Write-Host "Workspace root:        $WorkspaceRoot"
    Write-Host "Output root:           $OutputRoot"
    Write-Host "Scope:                 $($scopeDetails.Name)"
    Write-Host "Planning estimate:     $($scopeDetails.Estimate)"
    Write-Host "Throttle limit:        $ThrottleLimit"
    Write-Host "Maximum repositories:  $MaxRepositories"
    Write-Host "Session timeout:       $SessionTimeoutMinutes minutes"
    Write-Host "Public research:       $publicResearchEnabled"
    Write-Host "Provenance research:   $provenanceResearchEnabled"
    if ($provenanceResearchEnabled) {
        Write-Host ("Provenance lookback:   $ProvenanceLookbackMonths months")
        Write-Host (
            "Provenance window:     $provenanceStartDate through $reviewDate"
        )
    }
    else {
        Write-Host 'Provenance window:     disabled'
    }
    Write-Host "Model:                 $Model"
    return
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedPlanHash) -and
    $effectivePlan.ApprovalHash -ne $ExpectedPlanHash) {
    [Console]::Error.WriteLine('approved plan changed; regenerate and reconfirm')
    [Console]::Error.WriteLine("Expected approval hash: $ExpectedPlanHash")
    [Console]::Error.WriteLine(
        "Resolved approval hash: $($effectivePlan.ApprovalHash)"
    )
    exit 2
}

if ($PlanOnly) {
    $planJson = $effectivePlan | ConvertTo-Json -Depth 6
    [Console]::Out.Write($planJson + [Environment]::NewLine)
    return
}

$copilotPath = Resolve-ApplicationPath -Name 'copilot'
$tarPath = Resolve-ApplicationPath -Name 'tar'
$gitPath = if ($null -ne $gitPath) {
    $gitPath
}
else {
    Resolve-ApplicationPath -Name 'git'
}
$gitVersionText = (& $gitPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or
    $gitVersionText -notmatch '(?i)git version (\d+)\.(\d+)') {
    throw "Could not determine the installed Git version: $gitVersionText"
}
$gitMajorVersion = [int] $Matches[1]
$gitMinorVersion = [int] $Matches[2]
if ($gitMajorVersion -lt 2 -or
    ($gitMajorVersion -eq 2 -and $gitMinorVersion -lt 41)) {
    throw 'Git 2.41 or newer is required for DNS-pinned public HTTPS clones.'
}

[Console]::Out.Write((ConvertTo-ReviewPlanText -Plan $effectivePlan))
if (Test-InteractiveConsole) {
    $confirmInput = (Read-Host 'Run this review plan? [y/N]').Trim()
    if ($confirmInput -notmatch '^(?i:y|yes)$') {
        [Console]::Error.WriteLine('Review plan cancelled.')
        exit 1
    }
}
[Console]::Out.WriteLine(
    "Starting $scopeName; public research " +
    "$(Get-StatusWord -Enabled $publicResearchEnabled); provenance " +
    "$(Get-StatusWord -Enabled $provenanceResearchEnabled)."
)

$runId = (
    (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 16)
)
$runStartInstant = [DateTimeOffset]::UtcNow
$runStartedAt = $runStartInstant.ToString('o')
$runPlanStartedAt = $runStartInstant.ToString(
    'yyyy-MM-ddTHH:mm:ssZ',
    [Globalization.CultureInfo]::InvariantCulture
)
$runWorkspace = Join-Path $WorkspaceRoot $runId
$runResults = Join-Path $OutputRoot $runId
$sourceCopilotHome = if (
    -not [string]::IsNullOrWhiteSpace($env:COPILOT_HOME)
) {
    [IO.Path]::GetFullPath($env:COPILOT_HOME)
}
else {
    Join-Path $HOME '.copilot'
}
$copilotAuthBridge = Get-CopilotAuthenticationBridge `
    -CopilotHome $sourceCopilotHome
$copilotAuthBridgeJson = $copilotAuthBridge.Json.TrimEnd()
$copilotAuthBridgeHasPlaintextTokens =
    $copilotAuthBridge.HasPlaintextTokens
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_CONFIG_GLOBAL = $nullDevice
$env:GIT_ATTR_NOSYSTEM = '1'
$env:GIT_DISCOVERY_ACROSS_FILESYSTEM = '1'
$env:GIT_LFS_SKIP_SMUDGE = '1'
$env:GIT_NO_REPLACE_OBJECTS = '1'
$env:GIT_OPTIONAL_LOCKS = '0'
$env:GIT_TERMINAL_PROMPT = '0'
$authenticationVariables = @(
    'COPILOT_GITHUB_TOKEN'
    'GH_TOKEN'
    'GITHUB_TOKEN'
    'COPILOT_PROVIDER_API_KEY'
    'COPILOT_PROVIDER_BEARER_TOKEN'
    'ANTHROPIC_API_KEY'
    'AZURE_OPENAI_API_KEY'
    'OPENAI_API_KEY'
    'CAPI_HMAC_KEY'
    'COPILOT_HMAC_KEY'
    'GITHUB_COPILOT_API_TOKEN'
)
Write-Host (
    'Copilot authentication will be verified by the first isolated review ' +
    'session using the current environment, system credential store, GitHub ' +
    'CLI fallback, configured provider, or an ephemeral local auth bridge.'
)

foreach ($job in $jobs) {
    $job.CurlResolve = Resolve-PublicRepositoryEndpoint `
        -RepositoryHost $job.RepositoryHost `
        -Port $job.RepositoryPort
}

New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$WorkspaceRoot = Resolve-CanonicalDirectoryPath -Path $WorkspaceRoot
$OutputRoot = Resolve-CanonicalDirectoryPath -Path $OutputRoot
if ((Test-PathContains -Parent $WorkspaceRoot -Child $OutputRoot) -or
    (Test-PathContains -Parent $OutputRoot -Child $WorkspaceRoot)) {
    throw (
        'The writable output root and read-only checkout workspace became ' +
        "overlapping. Workspace: $WorkspaceRoot; output: $OutputRoot"
    )
}
Assert-PathOutsideGitRepository `
    -Path $WorkspaceRoot `
    -Label 'The checkout workspace root' `
    -GitPath $gitPath
Assert-PathOutsideGitRepository `
    -Path $OutputRoot `
    -Label 'The artifact output root' `
    -GitPath $gitPath
$runWorkspace = Join-Path $WorkspaceRoot $runId
$runResults = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runWorkspace -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path $runResults -ErrorAction Stop | Out-Null
$runWorkspace = Resolve-CanonicalDirectoryPath -Path $runWorkspace
$runResults = Resolve-CanonicalDirectoryPath -Path $runResults
if (-not (Test-PathContains -Parent $WorkspaceRoot -Child $runWorkspace) -or
    -not (Test-PathContains -Parent $OutputRoot -Child $runResults) -or
    (Test-PathContains -Parent $runWorkspace -Child $runResults) -or
    (Test-PathContains -Parent $runResults -Child $runWorkspace)) {
    throw 'Run-specific checkout and output directories are not safely disjoint.'
}
$reviewPlanJsonPath = Join-Path $runResults 'review-plan.json'
$reviewPlanTextPath = Join-Path $runResults 'review-plan.txt'
$runReviewPlan = New-ReviewPlan `
    -Sources $jobs.ToArray() `
    -GeneratedAt $planGeneratedAt `
    -ReviewDate $reviewDate `
    -WorkspaceRoot $WorkspaceRoot `
    -OutputRoot $OutputRoot `
    -ScopeNumber $Scope `
    -ScopeName $scopeName `
    -ScopeEstimate $scopeEstimate `
    -PublicResearch $publicResearchEnabled `
    -PriorArtLookbackMonths $defaultPriorArtLookbackMonths `
    -PriorArtStartDate $priorArtStartDate `
    -ProvenanceResearch $provenanceResearchEnabled `
    -ProvenanceLookbackMonths $ProvenanceLookbackMonths `
    -ProvenanceStartDate $provenanceStartDate `
    -SessionTimeoutMinutes $SessionTimeoutMinutes `
    -ThrottleLimit $ThrottleLimit `
    -MaxRepositories $MaxRepositories `
    -Model $Model `
    -OpenHtmlPolicy $openHtmlPolicy `
    -ApprovalHash $effectivePlan.ApprovalHash `
    -RunId $runId `
    -StartedAt $runPlanStartedAt
[IO.File]::WriteAllText(
    $reviewPlanJsonPath,
    (($runReviewPlan | ConvertTo-Json -Depth 6) + "`n"),
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $reviewPlanTextPath,
    (ConvertTo-ReviewPlanText -Plan $runReviewPlan),
    [Text.UTF8Encoding]::new($false)
)
Write-Host (
    "RHYOLITE PROGRESS | run | started | $($jobs.Count) repositories; " +
    "output $runResults"
)
$anonymousGitHome = Join-Path $runWorkspace '.anonymous-git-home'
New-Item -ItemType Directory -Path $anonymousGitHome -ErrorAction Stop |
    Out-Null

$results = @()
Write-Host (
    'RHYOLITE PROGRESS | run | preflight | verifying anonymous public ' +
    'access before clone or worker start'
)
$preflightFailures = [Collections.Generic.List[string]]::new()
foreach ($job in $jobs) {
    Write-Host (
        "RHYOLITE PROGRESS | $($job.Slug) | preflight | " +
        'checking anonymous public access'
    )
    $preflightResult = Test-RepositoryAccessibilityPreflight `
        -Job $job `
        -GitPath $gitPath `
        -RunWorkspace $runWorkspace `
        -AnonymousGitHome $anonymousGitHome `
        -NullDevice $nullDevice
    $job | Add-Member -NotePropertyName PreflightPassed `
        -NotePropertyValue $preflightResult.Passed -Force
    $job | Add-Member -NotePropertyName PreflightFailureSummary `
        -NotePropertyValue $preflightResult.FailureSummary -Force
    $job | Add-Member -NotePropertyName PreflightErrorText `
        -NotePropertyValue $preflightResult.ErrorText -Force
    $job | Add-Member -NotePropertyName PreflightExitCode `
        -NotePropertyValue $preflightResult.ExitCode -Force
    $job | Add-Member -NotePropertyName PreflightStartedAt `
        -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force

    if ($preflightResult.Passed) {
        $accessDetail = if ([string]::IsNullOrWhiteSpace($job.RequestedCommit)) {
            'anonymous access confirmed'
        }
        else {
            "anonymous access confirmed at $($job.RequestedCommit.Substring(0, 12))"
        }
        Write-Host "RHYOLITE PROGRESS | $($job.Slug) | preflight | $accessDetail"
    }
    else {
        $preflightFailures.Add($job.Url)
    }
}

if ($preflightFailures.Count -gt 0) {
    Write-Host (
        'RHYOLITE PROGRESS | run | preflight | approved plan failed closed; ' +
        'no clones or workers started'
    )
    $failingRepositoriesText = @(
        'Failing repositories:'
        @($preflightFailures | ForEach-Object { "- $_" })
    ) -join "`n"
    foreach ($job in $jobs) {
        if ($job.PreflightPassed) {
            $result = New-RepositoryResultSkeleton `
                -Job $job `
                -RunResults $runResults `
                -ScopeName $scopeName `
                -ScopeEstimate $scopeEstimate `
                -PublicResearch $publicResearchEnabled `
                -ProvenanceResearch $provenanceResearchEnabled `
                -Status 'PreflightBlocked' `
                -ExitCode 1 `
                -StartedAt $job.PreflightStartedAt
            $blockedErrorText = @"
Repository review did not start because another selected repository failed anonymous repository accessibility preflight.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Fail-closed policy: one inaccessible or anonymously unreadable source stops the whole approved plan before clone or worker start.
$failingRepositoriesText
"@.Trim()
            [IO.File]::WriteAllText(
                $result.Errors,
                ($blockedErrorText + "`n"),
                [Text.UTF8Encoding]::new($false)
            )
            $results += $result
        }
        else {
            $result = New-RepositoryResultSkeleton `
                -Job $job `
                -RunResults $runResults `
                -ScopeName $scopeName `
                -ScopeEstimate $scopeEstimate `
                -PublicResearch $publicResearchEnabled `
                -ProvenanceResearch $provenanceResearchEnabled `
                -Status 'AccessPreflightFailed' `
                -ExitCode $job.PreflightExitCode `
                -StartedAt $job.PreflightStartedAt
            [IO.File]::WriteAllText(
                $result.Errors,
                ($job.PreflightErrorText.TrimEnd() + "`n"),
                [Text.UTF8Encoding]::new($false)
            )
            $results += $result
        }
    }
}
else {
    Write-Host (
        'RHYOLITE PROGRESS | run | preflight | all selected repositories ' +
        'anonymously accessible'
    )
    $results = @(
        $jobs | ForEach-Object -Parallel {
        $job = $_
        Write-Host (
            "RHYOLITE PROGRESS | $($job.Slug) | clone | " +
            'anonymous public HTTPS clone started'
        )
        $startedAt = [DateTime]::UtcNow.ToString('o')
        $clonePath = Join-Path $using:runWorkspace "$($job.Slug)-readonly"
        $sessionRoot = Join-Path $using:runWorkspace "$($job.Slug)-session"
        $snapshotPath = Join-Path $sessionRoot 'source'
        $reviewPath = ''
        $repositoryResultPath = Join-Path $using:runResults $job.Slug
        $reportPath = Join-Path $repositoryResultPath 'review.txt'
        $markdownPath = Join-Path $repositoryResultPath 'review.md'
        $htmlPath = Join-Path $repositoryResultPath 'review.html'
        $timelinePath = Join-Path $repositoryResultPath 'analysis-timeline.txt'
        $transcriptPath = Join-Path $repositoryResultPath 'session.md'
        $requestPath = Join-Path $repositoryResultPath 'request.txt'
        $errorPath = Join-Path $repositoryResultPath 'errors.txt'
        $statePath = Join-Path $repositoryResultPath 'state.json'
        $handoffPath = Join-Path $repositoryResultPath 'handoff.md'
        $agentStatePath = Join-Path $repositoryResultPath 'agent-state'
        $copilotHomePath = Join-Path $agentStatePath 'copilot-home'
        $utf8 = [Text.UTF8Encoding]::new($false)
        $invokeAnonymousGit = {
            param(
                [Parameter(Mandatory)]
                [string[]] $Arguments
            )

            $gitProcess = [Diagnostics.Process]::new()
            $gitProcess.StartInfo = [Diagnostics.ProcessStartInfo]::new()
            $gitProcess.StartInfo.FileName = $using:gitPath
            $gitProcess.StartInfo.WorkingDirectory = $using:runWorkspace
            $gitProcess.StartInfo.UseShellExecute = $false
            $gitProcess.StartInfo.CreateNoWindow = $true
            $gitProcess.StartInfo.RedirectStandardOutput = $true
            $gitProcess.StartInfo.RedirectStandardError = $true
            foreach ($argument in $Arguments) {
                [void] $gitProcess.StartInfo.ArgumentList.Add($argument)
            }
            foreach ($name in @($gitProcess.StartInfo.Environment.Keys)) {
                if ($name -like 'GIT_*' -or
                    $name -like 'GCM_*' -or
                    $name -in @(
                        'COPILOT_GITHUB_TOKEN'
                        'GH_TOKEN'
                        'GITHUB_TOKEN'
                        'SSH_ASKPASS'
                        'SSH_AUTH_SOCK'
                        'NETRC'
                        'HTTP_PROXY'
                        'HTTPS_PROXY'
                        'ALL_PROXY'
                        'NO_PROXY'
                    )) {
                    [void] $gitProcess.StartInfo.Environment.Remove($name)
                }
            }
            $gitProcess.StartInfo.Environment['HOME'] = $using:anonymousGitHome
            $gitProcess.StartInfo.Environment['USERPROFILE'] =
                $using:anonymousGitHome
            $gitProcess.StartInfo.Environment['XDG_CONFIG_HOME'] =
                $using:anonymousGitHome
            $gitProcess.StartInfo.Environment['CURL_HOME'] =
                $using:anonymousGitHome
            $gitProcess.StartInfo.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
            $gitProcess.StartInfo.Environment['GIT_CONFIG_GLOBAL'] =
                $using:nullDevice
            $gitProcess.StartInfo.Environment['GIT_ATTR_NOSYSTEM'] = '1'
            $gitProcess.StartInfo.Environment[
                'GIT_DISCOVERY_ACROSS_FILESYSTEM'
            ] = '1'
            $gitProcess.StartInfo.Environment['GIT_LFS_SKIP_SMUDGE'] = '1'
            $gitProcess.StartInfo.Environment['GIT_NO_REPLACE_OBJECTS'] = '1'
            $gitProcess.StartInfo.Environment['GIT_OPTIONAL_LOCKS'] = '0'
            $gitProcess.StartInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'

            try {
                if (-not $gitProcess.Start()) {
                    throw 'Git process did not start.'
                }
                $stdoutTask = $gitProcess.StandardOutput.ReadToEndAsync()
                $stderrTask = $gitProcess.StandardError.ReadToEndAsync()
                $gitProcess.WaitForExit()
                $stdout = $stdoutTask.GetAwaiter().GetResult().TrimEnd()
                $stderr = $stderrTask.GetAwaiter().GetResult().TrimEnd()
                $combined = @(
                    $stdout
                    $stderr
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                [pscustomobject]@{
                    ExitCode = $gitProcess.ExitCode
                    Output = $combined -join "`n"
                }
            }
            finally {
                $gitProcess.Dispose()
            }
        }

        New-Item -ItemType Directory -Path $repositoryResultPath -Force |
            Out-Null

        $env:GIT_CONFIG_NOSYSTEM = '1'
        $env:GIT_CONFIG_GLOBAL = $using:nullDevice
        $env:GIT_LFS_SKIP_SMUDGE = '1'
        $env:GIT_TERMINAL_PROMPT = '0'

        $cloneResult = & $invokeAnonymousGit -Arguments @(
            '-c'
            "core.hooksPath=$using:nullDevice"
            '-c'
            'protocol.allow=never'
            '-c'
            'protocol.https.allow=always'
            '-c'
            'protocol.file.allow=never'
            '-c'
            'protocol.ext.allow=never'
            '-c'
            'credential.helper='
            '-c'
            'credential.interactive=false'
            '-c'
            'http.extraHeader='
            '-c'
            'http.proxy='
            '-c'
            'http.sslVerify=true'
            '-c'
            'http.followRedirects=false'
            '-c'
            "http.curloptResolve=$($job.CurlResolve)"
            'clone'
            '--quiet'
            '--filter=blob:none'
            '--no-recurse-submodules'
            '--'
            $job.Url
            $clonePath
        )
        $cloneOutput = $cloneResult.Output
        $cloneExitCode = $cloneResult.ExitCode

        if ($cloneExitCode -ne 0) {
            [IO.File]::WriteAllText(
                $errorPath,
                ($cloneOutput.TrimEnd() + "`n"),
                $utf8
            )
            return [pscustomobject]@{
                Slug = $job.Slug
                Repository = $job.Url
                SourceKind = $job.SourceKind
                SourcePath = $job.SourcePath
                RequestedCommit = $job.RequestedCommit
                SessionId = $null
                Session = $null
                Commit = $null
                Status = 'CloneFailed'
                ExitCode = $cloneExitCode
                StartedAt = $startedAt
                CompletedAt = [DateTime]::UtcNow.ToString('o')
                Scope = $using:scopeName
                ScopeEstimate = $using:scopeEstimate
                PublicResearch = $using:publicResearchEnabled
                ProvenanceResearch = $using:provenanceResearchEnabled
                Checkout = $reviewPath
                VerificationClone = $clonePath
                OutputDirectory = $repositoryResultPath
                PlainText = $reportPath
                Markdown = $markdownPath
                Html = $htmlPath
                Timeline = $timelinePath
                Transcript = $transcriptPath
                Request = $requestPath
                Errors = $errorPath
                State = $statePath
                Handoff = $handoffPath
            }
            Write-Host (
                "RHYOLITE PROGRESS | $($job.Slug) | artifacts | " +
                "$($result.Status); $repositoryResultPath"
            )
            $result
        }
        Write-Host (
            "RHYOLITE PROGRESS | $($job.Slug) | clone | clone completed"
        )

        if ($job.RequestedCommit) {
            $commitObject = "$($job.RequestedCommit)^{commit}"
            $commitSetupOutput = @(
                & $using:gitPath -C $clonePath cat-file -e $commitObject 2>&1
            )
            $commitSetupExitCode = $LASTEXITCODE
            if ($commitSetupExitCode -ne 0) {
                $fetchResult = & $invokeAnonymousGit -Arguments @(
                    '-C'
                    $clonePath
                    '-c'
                    "core.hooksPath=$using:nullDevice"
                    '-c'
                    'protocol.allow=never'
                    '-c'
                    'protocol.https.allow=always'
                    '-c'
                    'protocol.file.allow=never'
                    '-c'
                    'protocol.ext.allow=never'
                    '-c'
                    'credential.helper='
                    '-c'
                    'credential.interactive=false'
                    '-c'
                    'http.extraHeader='
                    '-c'
                    'http.proxy='
                    '-c'
                    'http.sslVerify=true'
                    '-c'
                    'http.followRedirects=false'
                    '-c'
                    "http.curloptResolve=$($job.CurlResolve)"
                    'fetch'
                    '--quiet'
                    '--no-tags'
                    'origin'
                    $job.RequestedCommit
                )
                $commitSetupOutput += $fetchResult.Output
                $commitSetupExitCode = $fetchResult.ExitCode
            }
            if ($commitSetupExitCode -eq 0) {
                $commitSetupOutput += @(
                    & $using:gitPath `
                        -C $clonePath `
                        -c "core.hooksPath=$using:nullDevice" `
                        checkout `
                        --quiet `
                        --detach `
                        $job.RequestedCommit 2>&1
                )
                $commitSetupExitCode = $LASTEXITCODE
            }
            if ($commitSetupExitCode -ne 0) {
                [IO.File]::WriteAllText(
                    $errorPath,
                    (($commitSetupOutput -join "`n") + "`n"),
                    $utf8
                )
                return [pscustomobject]@{
                    Slug = $job.Slug
                    Repository = $job.Url
                    SourceKind = $job.SourceKind
                    SourcePath = $job.SourcePath
                    RequestedCommit = $job.RequestedCommit
                    SessionId = $null
                    Session = $null
                    Commit = $null
                    Status = 'CommitResolutionFailed'
                    ExitCode = $commitSetupExitCode
                    StartedAt = $startedAt
                    CompletedAt = [DateTime]::UtcNow.ToString('o')
                    Scope = $using:scopeName
                    ScopeEstimate = $using:scopeEstimate
                    PublicResearch = $using:publicResearchEnabled
                    ProvenanceResearch = $using:provenanceResearchEnabled
                    Checkout = $reviewPath
                    VerificationClone = $clonePath
                    OutputDirectory = $repositoryResultPath
                    PlainText = $reportPath
                    Markdown = $markdownPath
                    Html = $htmlPath
                    Timeline = $timelinePath
                    Transcript = $transcriptPath
                    Request = $requestPath
                    Errors = $errorPath
                    State = $statePath
                    Handoff = $handoffPath
                }
            }
        }

        $commitOutput = & $using:gitPath -C $clonePath rev-parse HEAD 2>&1
        $commitExitCode = $LASTEXITCODE
        if ($commitExitCode -ne 0) {
            [IO.File]::WriteAllText(
                $errorPath,
                (($commitOutput -join "`n") + "`n"),
                $utf8
            )
            return [pscustomobject]@{
                Slug = $job.Slug
                Repository = $job.Url
                SourceKind = $job.SourceKind
                SourcePath = $job.SourcePath
                RequestedCommit = $job.RequestedCommit
                SessionId = $null
                Session = $null
                Commit = $null
                Status = 'CommitResolutionFailed'
                ExitCode = $commitExitCode
                StartedAt = $startedAt
                CompletedAt = [DateTime]::UtcNow.ToString('o')
                Scope = $using:scopeName
                ScopeEstimate = $using:scopeEstimate
                PublicResearch = $using:publicResearchEnabled
                ProvenanceResearch = $using:provenanceResearchEnabled
                Checkout = $reviewPath
                VerificationClone = $clonePath
                OutputDirectory = $repositoryResultPath
                PlainText = $reportPath
                Markdown = $markdownPath
                Html = $htmlPath
                Timeline = $timelinePath
                Transcript = $transcriptPath
                Request = $requestPath
                Errors = $errorPath
                State = $statePath
                Handoff = $handoffPath
            }
        }

        $commit = ($commitOutput | Select-Object -First 1).Trim()
        if ($job.RequestedCommit -and
            $commit -ne $job.RequestedCommit.ToLowerInvariant()) {
            [IO.File]::WriteAllText(
                $errorPath,
                (
                    "Resolved commit $commit does not match requested commit " +
                    "$($job.RequestedCommit).`n"
                ),
                $utf8
            )
            return [pscustomobject]@{
                Slug = $job.Slug
                Repository = $job.Url
                SourceKind = $job.SourceKind
                SourcePath = $job.SourcePath
                RequestedCommit = $job.RequestedCommit
                SessionId = $null
                Session = $null
                Commit = $commit
                Status = 'CommitResolutionFailed'
                ExitCode = 1
                StartedAt = $startedAt
                CompletedAt = [DateTime]::UtcNow.ToString('o')
                Scope = $using:scopeName
                ScopeEstimate = $using:scopeEstimate
                PublicResearch = $using:publicResearchEnabled
                ProvenanceResearch = $using:provenanceResearchEnabled
                Checkout = $reviewPath
                VerificationClone = $clonePath
                OutputDirectory = $repositoryResultPath
                PlainText = $reportPath
                Markdown = $markdownPath
                Html = $htmlPath
                Timeline = $timelinePath
                Transcript = $transcriptPath
                Request = $requestPath
                Errors = $errorPath
                State = $statePath
                Handoff = $handoffPath
            }
        }

        Import-Module $using:outputModulePath -Force
        $trackedFileCountOutput = & $using:gitPath -C $clonePath ls-files 2>&1 |
            Measure-Object -Line
        $trackedFileCount = if ($LASTEXITCODE -eq 0) {
            $trackedFileCountOutput.Lines
        }
        else {
            'unavailable'
        }
        $topLevelEntries = @(
            & $using:gitPath -C $clonePath ls-tree --name-only HEAD 2>&1 |
                Select-Object -First 200 |
                ForEach-Object {
                    if ($_.Length -gt 512) { $_.Substring(0, 512) } else { $_ }
                }
        )
        $refs = @(
            & $using:gitPath `
                -C $clonePath `
                for-each-ref `
                '--format=%(refname)%09%(objectname)' `
                refs/heads `
                refs/remotes `
                refs/tags 2>&1 |
                Select-Object -First 200 |
                ForEach-Object {
                    if ($_.Length -gt 512) { $_.Substring(0, 512) } else { $_ }
                }
        )
        $history = @(
            & $using:gitPath `
                -C $clonePath `
                log `
                --no-show-signature `
                -n 100 `
                --date=iso-strict `
                '--pretty=format:%H%x09%ad%x09%<(128,trunc)%an%x09%<(256,trunc)%s' 2>&1 |
                ForEach-Object {
                    if ($_.Length -gt 512) { $_.Substring(0, 512) } else { $_ }
                }
        )
        $repositoryMetadata = @"
TRUSTED WRAPPER-SUPPLIED GIT METADATA
The child sees a read-only, .git-free source snapshot archived from a pristine
clone detached at the exact commit below. Direct shell and Git tools are
intentionally unavailable to the child agent.

Source type: $($job.SourceKind)
Remote URL: $($job.Url)
HEAD: $commit
Tracked file count: $trackedFileCount

Top-level tracked entries (maximum 200):
$($topLevelEntries -join "`n")

Refs (maximum 200):
$($refs -join "`n")

Recent commit history (maximum 100; author email addresses omitted):
$($history -join "`n")
"@
        $repositoryMetadata = ConvertTo-ReviewPlainText `
            -Text $repositoryMetadata `
            -RedactEmails `
            -RedactCredentials
        if ($repositoryMetadata.Length -gt 65536) {
            $repositoryMetadata =
                $repositoryMetadata.Substring(0, 65536).TrimEnd() +
                "`n[trusted metadata truncated by wrapper]"
        }

        New-Item -ItemType Directory -Path $sessionRoot -ErrorAction Stop |
            Out-Null
        New-Item -ItemType Directory -Path $snapshotPath -ErrorAction Stop |
            Out-Null

        $archivePath = Join-Path $sessionRoot 'source.tar'
        $snapshotOutput = @()
        $attributePathOutput = @(
            & $using:gitPath `
                -C $clonePath `
                rev-parse `
                --git-path info/attributes 2>&1
        )
        $snapshotExitCode = $LASTEXITCODE
        if ($snapshotExitCode -eq 0) {
            $attributePath = $attributePathOutput[0].Trim()
            if (-not [IO.Path]::IsPathRooted($attributePath)) {
                $attributePath = Join-Path $clonePath $attributePath
            }
            $attributePath = [IO.Path]::GetFullPath($attributePath)
            $attributeDirectory = Split-Path -Parent $attributePath
            New-Item -ItemType Directory -Path $attributeDirectory -Force |
                Out-Null
            $hadAttributeFile = Test-Path -LiteralPath $attributePath -PathType Leaf
            $attributeBackup = if ($hadAttributeFile) {
                [IO.File]::ReadAllBytes($attributePath)
            }
            else {
                $null
            }
            try {
                [IO.File]::WriteAllText(
                    $attributePath,
                    "* -export-ignore -export-subst`n",
                    $utf8
                )
                $snapshotOutput = @(
                    & $using:gitPath `
                        -C $clonePath `
                        -c "core.hooksPath=$using:nullDevice" `
                        archive `
                        --format=tar `
                        "--output=$archivePath" `
                        $commit 2>&1
                )
                $snapshotExitCode = $LASTEXITCODE
            }
            finally {
                if ($hadAttributeFile) {
                    [IO.File]::WriteAllBytes($attributePath, $attributeBackup)
                }
                else {
                    Remove-Item -LiteralPath $attributePath -Force `
                        -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            $snapshotOutput += $attributePathOutput
        }
        if ($snapshotExitCode -eq 0) {
            $snapshotOutput += @(
                & $using:tarPath `
                    -xf $archivePath `
                    -C $snapshotPath 2>&1
            )
            $snapshotExitCode = $LASTEXITCODE
        }
        Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

        if ($snapshotExitCode -eq 0) {
            $links = @(
                Get-ChildItem -LiteralPath $snapshotPath -Recurse -Force |
                    Where-Object {
                        ($_.Attributes -band
                            [IO.FileAttributes]::ReparsePoint) -ne 0
                    } |
                    Sort-Object { $_.FullName.Length } -Descending
            )
            foreach ($link in $links) {
                $linkTarget = @($link.Target) -join ', '
                Remove-Item -LiteralPath $link.FullName -Recurse -Force
                [IO.File]::WriteAllText(
                    $link.FullName,
                    "Symbolic link target (not followed): $linkTarget`n",
                    $utf8
                )
            }
            Get-ChildItem -LiteralPath $snapshotPath -Recurse -Force -File |
                ForEach-Object { $_.IsReadOnly = $true }
            $reviewPath = $snapshotPath
        }
        else {
            [IO.File]::WriteAllText(
                $errorPath,
                (($snapshotOutput -join "`n") + "`n"),
                $utf8
            )
            return [pscustomobject]@{
                Slug = $job.Slug
                Repository = $job.Url
                SourceKind = $job.SourceKind
                SourcePath = $job.SourcePath
                RequestedCommit = $job.RequestedCommit
                SessionId = $null
                Session = $null
                Commit = $commit
                Status = 'SnapshotFailed'
                ExitCode = $snapshotExitCode
                StartedAt = $startedAt
                CompletedAt = [DateTime]::UtcNow.ToString('o')
                Scope = $using:scopeName
                ScopeEstimate = $using:scopeEstimate
                PublicResearch = $using:publicResearchEnabled
                ProvenanceResearch = $using:provenanceResearchEnabled
                Checkout = $reviewPath
                VerificationClone = $clonePath
                OutputDirectory = $repositoryResultPath
                PlainText = $reportPath
                Markdown = $markdownPath
                Html = $htmlPath
                Timeline = $timelinePath
                Transcript = $transcriptPath
                Request = $requestPath
                Errors = $errorPath
                State = $statePath
                Handoff = $handoffPath
            }
        }
        Write-Host (
            "RHYOLITE PROGRESS | $($job.Slug) | snapshot | " +
            'read-only source snapshot prepared'
        )

        $prompt = $using:promptTemplate
        $prompt = $prompt.Replace('{{REPOSITORY_URL}}', $job.Url)
        $prompt = $prompt.Replace('{{REPOSITORY_PATH}}', $reviewPath)
        $prompt = $prompt.Replace('{{COMMIT}}', $commit)
        $prompt = $prompt.Replace('{{REVIEW_DATE}}', $using:reviewDate)
        $prompt = $prompt.Replace(
            '{{PRIOR_ART_START_DATE}}',
            $using:priorArtStartDate
        )
        $prompt = $prompt.Replace(
            '{{PROVENANCE_LOOKBACK_MONTHS}}',
            $using:provenanceLookbackPromptValue
        )
        $prompt = $prompt.Replace(
            '{{PROVENANCE_START_DATE}}',
            $using:provenanceStartDatePromptValue
        )
        $prompt = $prompt.Replace('{{SCOPE_NAME}}', $using:scopeName)
        $prompt = $prompt.Replace(
            '{{OUTPUT_DIRECTORY}}',
            $repositoryResultPath
        )
        $prompt = $prompt.Replace(
            '{{REPOSITORY_METADATA}}',
            $repositoryMetadata
        )
        $prompt = $prompt.Replace(
            '{{PUBLIC_RESEARCH_INSTRUCTIONS}}',
            $using:publicResearchInstructions
        )
        $prompt = $prompt.Replace(
            '{{PROVENANCE_INSTRUCTIONS}}',
            $using:provenanceInstructions
        )
        [IO.File]::WriteAllText(
            $requestPath,
            ($prompt.TrimEnd() + "`n"),
            $utf8
        )

        $sessionId = [guid]::NewGuid().ToString()
        $sessionSuffix = "-$using:runId"
        $sessionPrefix = 'review-'
        $maximumSlugLength =
            96 - $sessionPrefix.Length - $sessionSuffix.Length
        $sessionSlug = if ($job.Slug.Length -gt $maximumSlugLength) {
            $job.Slug.Substring(0, $maximumSlugLength)
        }
        else {
            $job.Slug
        }
        $sessionName = "$sessionPrefix$sessionSlug$sessionSuffix"

        $copilotArguments = [Collections.Generic.List[string]]::new()
        $availableToolNames = @(
            'view'
            'glob'
            'rg'
            'skill'
            'task'
            'list_agents'
            'read_agent'
        )
        if ($using:publicResearchEnabled) {
            $availableToolNames += 'web_fetch'
        }
        $availableTools = $availableToolNames -join ','
        @(
            '-C'
            $sessionRoot
            '--plugin-dir'
            $using:pluginRoot
            '--name'
            $sessionName
            '--session-id'
            $sessionId
            '--agent'
            'rhyolite:repo-review-worker'
            '--model'
            $using:Model
            '--context'
            'long_context'
            '--no-ask-user'
            '--no-color'
            '--no-custom-instructions'
            '--disable-builtin-mcps'
            '--disallow-temp-dir'
            '--no-remote-export'
            '--secret-env-vars'
            ($using:authenticationVariables -join ',')
            '--available-tools'
            $availableTools
            '--allow-tool'
            'read'
            '--deny-tool'
            'write'
            '--deny-tool'
            'shell'
            '--stream'
            'off'
            '--share'
            $transcriptPath
            '--silent'
        ) | ForEach-Object { $copilotArguments.Add($_) }

        if ($using:publicResearchEnabled) {
            $copilotArguments.Add('--allow-all-urls')
        }

        $runtimeCopilotHomePath = Join-Path (
            [IO.Path]::GetTempPath()
        ) (
            'rhyolite-repo-review-copilot-' + [guid]::NewGuid().ToString('N')
        )
        $copilotExitCode = 1
        $outputText = ''
        $errorText = ''
        $postProcessFailure = $false
        $directoryMode = [IO.UnixFileMode]::UserRead -bor
            [IO.UnixFileMode]::UserWrite -bor
            [IO.UnixFileMode]::UserExecute
        $fileMode = [IO.UnixFileMode]::UserRead -bor
            [IO.UnixFileMode]::UserWrite
        try {
            New-Item -ItemType Directory -Path $runtimeCopilotHomePath |
                Out-Null
            if (-not [OperatingSystem]::IsWindows()) {
                [IO.File]::SetUnixFileMode(
                    $runtimeCopilotHomePath,
                    $directoryMode
                )
            }
            $runtimeSettings = if (
                $using:copilotAuthBridgeHasPlaintextTokens
            ) {
                (
                    "{`n" +
                    "  `"storeTokenPlaintext`": true,`n" +
                    "  `"disableAllHooks`": true,`n" +
                    "  `"customAgents`": {`n" +
                    "    `"defaultLocalOnly`": true`n" +
                    "  }`n" +
                    "}`n"
                )
            }
            else {
                (
                    "{`n" +
                    "  `"disableAllHooks`": true,`n" +
                    "  `"customAgents`": {`n" +
                    "    `"defaultLocalOnly`": true`n" +
                    "  }`n" +
                    "}`n"
                )
            }
            $runtimeSettingsPath = Join-Path `
                $runtimeCopilotHomePath `
                'settings.json'
            $runtimeConfigPath = Join-Path `
                $runtimeCopilotHomePath `
                'config.json'
            [IO.File]::WriteAllText(
                $runtimeSettingsPath,
                $runtimeSettings,
                $utf8
            )
            [IO.File]::WriteAllText(
                $runtimeConfigPath,
                (
                    "// User settings belong in settings.json.`n" +
                    "// This file is managed automatically.`n" +
                    $using:copilotAuthBridgeJson +
                    "`n"
                ),
                $utf8
            )
            if (-not [OperatingSystem]::IsWindows()) {
                [IO.File]::SetUnixFileMode($runtimeSettingsPath, $fileMode)
                [IO.File]::SetUnixFileMode($runtimeConfigPath, $fileMode)
            }

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName = $using:copilotPath
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void] $process.StartInfo.Environment.Remove('COPILOT_ALLOW_ALL')
        [void] $process.StartInfo.Environment.Remove('COPILOT_SKILLS_DIRS')
        [void] $process.StartInfo.Environment.Remove(
            'COPILOT_CUSTOM_INSTRUCTIONS_DIRS'
        )
        [void] $process.StartInfo.Environment.Remove(
            'COPILOT_DYNAMIC_RETRIEVAL_SKILLS'
        )
        [void] $process.StartInfo.Environment.Remove(
            'COPILOT_EMBEDDING_ONLY_SKILLS'
        )
        $process.StartInfo.Environment['COPILOT_HOME'] =
            $runtimeCopilotHomePath
        foreach ($argument in $copilotArguments) {
            $process.StartInfo.ArgumentList.Add($argument)
        }

        Write-Host (
            "RHYOLITE PROGRESS | $($job.Slug) | analysis | " +
            "$using:Model review started; scope $using:Scope"
        )
        try {
            [void] $process.Start()
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write($prompt)
            $process.StandardInput.Close()

            $analysisStarted = [DateTimeOffset]::UtcNow
            $analysisDeadline = $analysisStarted.AddMinutes(
                $using:SessionTimeoutMinutes
            )
            while (-not $process.WaitForExit(30000)) {
                $now = [DateTimeOffset]::UtcNow
                if ($now -ge $analysisDeadline) {
                    $process.Kill($true)
                    $process.WaitForExit()
                    $copilotExitCode = 124
                    break
                }
                $elapsed = $now - $analysisStarted
                Write-Host (
                    "RHYOLITE PROGRESS | $($job.Slug) | analysis | " +
                    "still running; elapsed $([int] $elapsed.TotalMinutes)m " +
                    "$($elapsed.Seconds)s"
                )
            }
            if ($copilotExitCode -ne 124) {
                $copilotExitCode = $process.ExitCode
            }

            $outputText = $outputTask.GetAwaiter().GetResult()
            $errorText = $errorTask.GetAwaiter().GetResult()
            Write-Host (
                "RHYOLITE PROGRESS | $($job.Slug) | analysis | " +
                'agent response received'
            )
        }
        catch {
            $copilotExitCode = 1
            $outputText = ''
            $errorText = $_.Exception.ToString()
        }
        finally {
            $process.Dispose()
        }

            New-Item -ItemType Directory -Path $copilotHomePath -Force |
                Out-Null
            if (-not [OperatingSystem]::IsWindows()) {
                [IO.File]::SetUnixFileMode(
                    $copilotHomePath,
                    $directoryMode
                )
            }
            $persistedSettingsPath = Join-Path `
                $copilotHomePath `
                'settings.json'
            $persistedConfigPath = Join-Path `
                $copilotHomePath `
                'config.json'
            [IO.File]::WriteAllText(
                $persistedSettingsPath,
                (
                    "{`n" +
                    "  `"disableAllHooks`": true,`n" +
                    "  `"customAgents`": {`n" +
                    "    `"defaultLocalOnly`": true`n" +
                    "  }`n" +
                    "}`n"
                ),
                $utf8
            )
            [IO.File]::WriteAllText(
                $persistedConfigPath,
                (
                    "// User settings belong in settings.json.`n" +
                    "// This file is managed automatically.`n" +
                    "{}`n"
                ),
                $utf8
            )
            foreach ($entryName in @('session-state', 'session-store')) {
                $sourceEntry = Join-Path $runtimeCopilotHomePath $entryName
                if (-not (
                    Test-Path -LiteralPath $sourceEntry -PathType Container
                )) {
                    continue
                }

                $destinationEntry = Join-Path $copilotHomePath $entryName
                New-Item -ItemType Directory -Path $destinationEntry -Force |
                    Out-Null
                foreach ($file in @(
                    Get-ChildItem -LiteralPath $sourceEntry -File -Recurse -Force
                )) {
                    if (
                        ($file.Attributes -band
                            [IO.FileAttributes]::ReparsePoint) -ne 0
                    ) {
                        continue
                    }
                    $relativePath = [IO.Path]::GetRelativePath(
                        $sourceEntry,
                        $file.FullName
                    )
                    $destinationFile = Join-Path `
                        $destinationEntry `
                        $relativePath
                    $destinationDirectory = Split-Path `
                        -Parent `
                        $destinationFile
                    New-Item -ItemType Directory `
                        -Path $destinationDirectory `
                        -Force |
                        Out-Null
                    Copy-Item -LiteralPath $file.FullName `
                        -Destination $destinationFile `
                        -Force
                }
            }
            if (-not [OperatingSystem]::IsWindows()) {
                foreach ($directory in @(
                    Get-Item -LiteralPath $copilotHomePath -Force
                    Get-ChildItem -LiteralPath $copilotHomePath `
                        -Directory `
                        -Recurse `
                        -Force
                )) {
                    [IO.File]::SetUnixFileMode(
                        $directory.FullName,
                        $directoryMode
                    )
                }
                foreach ($file in @(
                    Get-ChildItem -LiteralPath $copilotHomePath `
                        -File `
                        -Recurse `
                        -Force
                )) {
                    [IO.File]::SetUnixFileMode($file.FullName, $fileMode)
                }
            }
        }
        catch {
            $copilotExitCode = 1
            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $errorText = $errorText.TrimEnd() + "`n"
            }
            $errorText += (
                'Trusted wrapper failure: ' +
                $_.Exception.ToString().TrimEnd() +
                "`n"
            )
        }
        finally {
            if (
                -not [string]::IsNullOrWhiteSpace(
                    $runtimeCopilotHomePath
                ) -and
                (Test-Path -LiteralPath $runtimeCopilotHomePath)
            ) {
                $cleanupMessages = [Collections.Generic.List[string]]::new()
                $runtimeConfigCleanupPath = Join-Path `
                    $runtimeCopilotHomePath `
                    'config.json'
                if (
                    Test-Path -LiteralPath `
                        $runtimeConfigCleanupPath `
                        -PathType Leaf
                ) {
                    try {
                        Remove-Item -LiteralPath $runtimeConfigCleanupPath `
                            -Force `
                            -ErrorAction Stop
                    }
                    catch {
                        try {
                            [IO.File]::WriteAllText(
                                $runtimeConfigCleanupPath,
                                (
                                    "// User settings belong in settings.json.`n" +
                                    "// This file is managed automatically.`n" +
                                    "{}`n"
                                ),
                                $utf8
                            )
                            if (-not [OperatingSystem]::IsWindows()) {
                                [IO.File]::SetUnixFileMode(
                                    $runtimeConfigCleanupPath,
                                    $fileMode
                                )
                            }
                        }
                        catch {
                            $cleanupMessages.Add(
                                'Could not sanitize the temporary Copilot ' +
                                'authentication configuration.'
                            )
                        }
                    }
                }

                $lastCleanupError = ''
                for ($attempt = 0; $attempt -lt 3; $attempt++) {
                    try {
                        Remove-Item -LiteralPath $runtimeCopilotHomePath `
                            -Recurse `
                            -Force `
                            -ErrorAction Stop
                    }
                    catch {
                        $lastCleanupError = $_.Exception.Message
                    }
                    if (-not (
                        Test-Path -LiteralPath $runtimeCopilotHomePath
                    )) {
                        break
                    }
                    Start-Sleep -Milliseconds 200
                }
                if (Test-Path -LiteralPath $runtimeCopilotHomePath) {
                    $cleanupMessages.Add(
                        'Could not remove the temporary Copilot runtime home ' +
                        "after three attempts: $runtimeCopilotHomePath. " +
                        "Last error: $lastCleanupError"
                    )
                }
                if ($cleanupMessages.Count -gt 0) {
                    $postProcessFailure = $true
                    if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                        $errorText = $errorText.TrimEnd() + "`n"
                    }
                    $errorText += (
                        ($cleanupMessages -join "`n") +
                        "`n"
                    )
                }
            }
        }

        Import-Module $using:outputModulePath -Force
        $outputText = ConvertTo-ReviewPlainText `
            -Text $outputText `
            -RedactEmails `
            -RedactCredentials
        $errorText = ConvertTo-ReviewPlainText `
            -Text $errorText `
            -RedactEmails `
            -RedactCredentials

        [IO.File]::WriteAllText(
            $timelinePath,
            ($outputText.TrimEnd() + "`n"),
            $utf8
        )
        $errorFileText = if ($errorText) {
            $errorText.TrimEnd() + "`n"
        }
        else {
            ''
        }
        [IO.File]::WriteAllText(
            $errorPath,
            $errorFileText,
            $utf8
        )

        if ($copilotExitCode -eq 0) {
            $extractedReport = Get-ReviewReport -Timeline $outputText
            if (-not $extractedReport.Found) {
                $copilotExitCode = 1
                $reportText =
                    "Final report extraction failed. See analysis-timeline.txt.`n"
                $errorText +=
                    "Final report header or end marker was not found.`n"
            }
            else {
                $reportText = $extractedReport.Text
                if (-not $extractedReport.HasClosingDelimiter) {
                    $copilotExitCode = 1
                    $errorText +=
                        "Incomplete report: final closing delimiter was missing; " +
                        "recovered text was saved through end of agent output.`n"
                }
                if ($extractedReport.ContainsMarkdownTable) {
                    $copilotExitCode = 1
                    $errorText +=
                        "Final report contains a Markdown table.`n"
                }
            }
        }
        elseif ($copilotExitCode -eq 124) {
            $reportText =
                "Repository review timed out. See analysis-timeline.txt.`n"
            $errorText +=
                "Session exceeded $using:SessionTimeoutMinutes minutes.`n"
        }
        else {
            $reportText =
                "Repository review failed. See errors.txt and " +
                "analysis-timeline.txt.`n"
        }
        if ($postProcessFailure) {
            $copilotExitCode = 1
        }

        $repositoryStatus = @(
            & $using:gitPath `
                -C $clonePath `
                status `
                --porcelain `
                --untracked-files=all 2>&1
        )
        $statusExitCode = $LASTEXITCODE
        $headAfterReview = @(
            & $using:gitPath -C $clonePath rev-parse HEAD 2>&1
        )
        $headExitCode = $LASTEXITCODE
        & $using:gitPath -C $clonePath diff --quiet --no-ext-diff
        $worktreeDiffExitCode = $LASTEXITCODE
        & $using:gitPath -C $clonePath diff --cached --quiet --no-ext-diff
        $indexDiffExitCode = $LASTEXITCODE
        if ($statusExitCode -ne 0 -or
            $repositoryStatus.Count -gt 0 -or
            $headExitCode -ne 0 -or
            $headAfterReview[0].Trim() -ne $commit -or
            $worktreeDiffExitCode -ne 0 -or
            $indexDiffExitCode -ne 0) {
            $copilotExitCode = 1
            $errorText +=
                "Policy violation: reviewed checkout is not clean.`n"
        }

        [IO.File]::WriteAllText(
            $reportPath,
            ($reportText.TrimEnd() + "`n"),
            $utf8
        )
        $errorFileText = if ($errorText) {
            $errorText.TrimEnd() + "`n"
        }
        else {
            ''
        }
        [IO.File]::WriteAllText(
            $errorPath,
            $errorFileText,
            $utf8
        )

        if (Test-Path -LiteralPath $transcriptPath -PathType Leaf) {
            $transcript = [IO.File]::ReadAllText($transcriptPath)
            $transcript = ConvertTo-ReviewPlainText `
                -Text $transcript `
                -RedactEmails `
                -RedactCredentials
            $transcript = ConvertTo-SafeMarkdownDocument `
                -Title 'Copilot Session Transcript' `
                -Text $transcript
            [IO.File]::WriteAllText($transcriptPath, $transcript, $utf8)
        }

        [pscustomobject]@{
            Slug = $job.Slug
            Repository = $job.Url
            SourceKind = $job.SourceKind
            SourcePath = $job.SourcePath
            RequestedCommit = $job.RequestedCommit
            SessionId = $sessionId
            Session = $sessionName
            Commit = $commit
            Status = if ($copilotExitCode -eq 0) {
                'Completed'
            }
            elseif ($copilotExitCode -eq 124) {
                'TimedOut'
            }
            else {
                'ReviewFailed'
            }
            ExitCode = $copilotExitCode
            StartedAt = $startedAt
            CompletedAt = [DateTime]::UtcNow.ToString('o')
            Scope = $using:scopeName
            ScopeEstimate = $using:scopeEstimate
            PublicResearch = $using:publicResearchEnabled
            ProvenanceResearch = $using:provenanceResearchEnabled
            Checkout = $reviewPath
            VerificationClone = $clonePath
            OutputDirectory = $repositoryResultPath
            PlainText = $reportPath
            Markdown = $markdownPath
            Html = $htmlPath
            Timeline = $timelinePath
            Transcript = $transcriptPath
            Request = $requestPath
            Errors = $errorPath
            State = $statePath
            Handoff = $handoffPath
        }
        } -ThrottleLimit $ThrottleLimit
    )
}

$utf8 = [Text.UTF8Encoding]::new($false)
Import-Module $outputModulePath -Force

foreach ($result in $results) {
    if (-not (Test-Path -LiteralPath $result.PlainText -PathType Leaf)) {
        $failureSummary = switch ($result.Status) {
            'AccessPreflightFailed' {
                'Anonymous repository accessibility preflight failed. Rhyolite currently supports only publicly accessible repositories and does not attempt authentication. See errors.txt.'
            }
            'PreflightBlocked' {
                'Repository review did not start because another selected repository failed anonymous repository accessibility preflight. Rhyolite currently supports only publicly accessible repositories and does not attempt authentication. See errors.txt.'
            }
            'CloneFailed' {
                'Repository clone failed. See errors.txt.'
            }
            'CommitResolutionFailed' {
                'Commit resolution failed. See errors.txt.'
            }
            'SnapshotFailed' {
                'Read-only source snapshot failed. See errors.txt.'
            }
            default {
                'Repository review did not produce a report. See errors.txt.'
            }
        }
        $fallbackReport = @"
================================================================================
REPOSITORY REVIEW REPORT
$failureSummary
================================================================================
"@
        [IO.File]::WriteAllText(
            $result.PlainText,
            ($fallbackReport.TrimEnd() + "`n"),
            $utf8
        )
    }

    foreach ($artifact in @(
        [pscustomobject]@{
            Path = $result.Timeline
            Content = ''
        }
        [pscustomobject]@{
            Path = $result.Transcript
            Content = "# Copilot session transcript`n`nNo completed session transcript is available.`n"
        }
        [pscustomobject]@{
            Path = $result.Request
            Content = "No review request was generated because the session did not start.`n"
        }
        [pscustomobject]@{
            Path = $result.Errors
            Content = ''
        }
    )) {
        if (-not (Test-Path -LiteralPath $artifact.Path -PathType Leaf)) {
            [IO.File]::WriteAllText(
                $artifact.Path,
                $artifact.Content,
                $utf8
            )
        }
    }
    $sanitizedErrors = ConvertTo-ReviewPlainText `
        -Text ([IO.File]::ReadAllText($result.Errors)) `
        -RedactEmails `
        -RedactCredentials
    [IO.File]::WriteAllText(
        $result.Errors,
        $(if ($sanitizedErrors) {
            $sanitizedErrors.TrimEnd() + "`n"
        }
        else {
            ''
        }),
        $utf8
    )

    $reportText = [IO.File]::ReadAllText($result.PlainText)
    $markdownText = ConvertTo-ReviewMarkdown -Text $reportText
    $htmlText = ConvertTo-ReviewHtml `
        -Text $reportText `
        -Repository $result.Repository `
        -Commit ([string] $result.Commit) `
        -Status $result.Status
    [IO.File]::WriteAllText($result.Markdown, $markdownText, $utf8)
    [IO.File]::WriteAllText($result.Html, $htmlText, $utf8)

    $artifacts = [ordered]@{
        PlainText = $result.PlainText
        Markdown = $result.Markdown
        Html = $result.Html
        Timeline = $result.Timeline
        Transcript = $result.Transcript
        Request = $result.Request
        Errors = $result.Errors
        State = $result.State
        Handoff = $result.Handoff
        AgentState = Join-Path $result.OutputDirectory 'agent-state'
    }
    New-Item -ItemType Directory -Path $artifacts.AgentState -Force |
        Out-Null
    $handoffText = New-ReviewHandoff `
        -Repository $result.Repository `
        -Commit ([string] $result.Commit) `
        -Status $result.Status `
        -Session ([string] $result.Session) `
        -SessionId ([string] $result.SessionId) `
        -SourceKind $result.SourceKind `
        -SourcePath $result.SourcePath `
        -Checkout $result.Checkout `
        -OutputDirectory $result.OutputDirectory `
        -Scope $result.Scope `
        -ScopeEstimate $result.ScopeEstimate `
        -ProvenanceWindow $provenanceWindowText `
        -Artifacts $artifacts
    [IO.File]::WriteAllText(
        $result.Handoff,
        ($handoffText.TrimEnd() + "`n"),
        $utf8
    )

    $state = [ordered]@{
        SchemaVersion = $stateSchemaVersion
        Slug = $result.Slug
        Repository = $result.Repository
        Source = [ordered]@{
            Kind = $result.SourceKind
            LocalPath = $result.SourcePath
            RemoteUrl = $result.Repository
        }
        RequestedCommit = [string] $result.RequestedCommit
        Commit = [string] $result.Commit
        Status = $result.Status
        ExitCode = $result.ExitCode
        StartedAt = $result.StartedAt
        CompletedAt = $result.CompletedAt
        Scope = [ordered]@{
            Name = $result.Scope
            PlanningEstimate = $result.ScopeEstimate
            PublicResearch = $result.PublicResearch
            ProvenanceResearch = $result.ProvenanceResearch
        }
        ProvenanceWindow = $provenanceWindowState
        Session = [ordered]@{
            Id = [string] $result.SessionId
            Name = [string] $result.Session
            ResumePolicy = 'Continue only through the trusted Rhyolite repo-review runner; do not invoke copilot --resume directly.'
        }
        Paths = [ordered]@{
            ReadOnlyCheckout = $result.Checkout
            VerificationClone = $result.VerificationClone
            WritableOutput = $result.OutputDirectory
        }
        Artifacts = $artifacts
    }
    [IO.File]::WriteAllText(
        $result.State,
        (($state | ConvertTo-Json -Depth 6) + "`n"),
        $utf8
    )
}

$manifestPath = Join-Path $runResults 'manifest.json'
$manifestEntries = @(
    $results | Sort-Object Repository | ForEach-Object {
        Get-Content -LiteralPath $_.State -Raw | ConvertFrom-Json
    }
)
$manifestText = $manifestEntries | ConvertTo-Json -Depth 8 -AsArray
[IO.File]::WriteAllText(
    $manifestPath,
    ($manifestText + "`n"),
    [Text.UTF8Encoding]::new($false)
)

Write-Host (
    'RHYOLITE PROGRESS | run | finalizing | ' +
    'building manifest, state, handoff, and HTML index'
)
$runCompletedAt = [DateTime]::UtcNow.ToString('o')
$runStatus = if (@($results | Where-Object Status -ne 'Completed').Count -eq 0) {
    'Completed'
}
elseif (@($results | Where-Object Status -eq 'Completed').Count -gt 0) {
    'Partial'
}
else {
    'Failed'
}
$runStatePath = Join-Path $runResults 'state.json'
$runHandoffPath = Join-Path $runResults 'handoff.md'
$indexPath = Join-Path $runResults 'index.html'
$runState = [ordered]@{
    SchemaVersion = $stateSchemaVersion
    RunId = $runId
    Status = $runStatus
    StartedAt = $runStartedAt
    CompletedAt = $runCompletedAt
    Scope = [ordered]@{
        Name = $scopeName
        PlanningEstimate = $scopeEstimate
        PublicResearch = $publicResearchEnabled
        ProvenanceResearch = $provenanceResearchEnabled
    }
    ProvenanceWindow = $provenanceWindowState
    Paths = [ordered]@{
        ReadOnlyWorkspace = $runWorkspace
        WritableOutput = $runResults
    }
    Artifacts = [ordered]@{
        ReviewPlanJson = $reviewPlanJsonPath
        ReviewPlanText = $reviewPlanTextPath
        Manifest = $manifestPath
        Handoff = $runHandoffPath
        HtmlIndex = $indexPath
    }
    Repositories = @(
        $results | Sort-Object Repository | ForEach-Object {
            [ordered]@{
                Repository = $_.Repository
                Source = [ordered]@{
                    Kind = $_.SourceKind
                    LocalPath = $_.SourcePath
                    RemoteUrl = $_.Repository
                }
                RequestedCommit = [string] $_.RequestedCommit
                Commit = [string] $_.Commit
                Status = $_.Status
                ProvenanceWindow = $provenanceWindowState
                State = $_.State
                Handoff = $_.Handoff
                Html = $_.Html
            }
        }
    )
}
[IO.File]::WriteAllText(
    $runStatePath,
    (($runState | ConvertTo-Json -Depth 7) + "`n"),
    $utf8
)

$runHandoffLines = [Collections.Generic.List[string]]::new()
$runHandoffLines.Add('# Repository review run handoff')
$runHandoffLines.Add('')
$addRunHandoffValue = {
    param([string] $Label, [AllowEmptyString()][string] $Value)
    $runHandoffLines.Add("${Label}:")
    $runHandoffLines.Add('')
    foreach ($line in (ConvertTo-ReviewPlainText -Text $Value) -split "`n") {
        $runHandoffLines.Add("    $line")
    }
    $runHandoffLines.Add('')
}
& $addRunHandoffValue 'Run ID' $runId
& $addRunHandoffValue 'Status' $runStatus
& $addRunHandoffValue 'Scope' $scopeName
& $addRunHandoffValue 'Planning estimate' $scopeEstimate
& $addRunHandoffValue 'Provenance window' $provenanceWindowText
& $addRunHandoffValue 'Read-only workspace' $runWorkspace
& $addRunHandoffValue 'Writable output' $runResults
@(
    '## Continue safely'
    ''
    'Open each repository handoff for its saved session identifiers and state.'
    'Do not invoke `copilot --resume` directly; continue through the trusted'
    'Rhyolite `repo-review` runner so all restrictions are re-established.'
    ''
    '## Repository sessions'
    ''
) | ForEach-Object { $runHandoffLines.Add($_) }
foreach ($result in $results | Sort-Object Repository) {
    & $addRunHandoffValue 'Repository' $result.Repository
    & $addRunHandoffValue 'Source kind' $result.SourceKind
    & $addRunHandoffValue 'Selected source path' $result.SourcePath
    & $addRunHandoffValue 'Status' $result.Status
    & $addRunHandoffValue 'Handoff' $result.Handoff
}
$runHandoffLines.Add('## Run artifacts')
$runHandoffLines.Add('')
& $addRunHandoffValue 'Review plan JSON' $reviewPlanJsonPath
& $addRunHandoffValue 'Review plan text' $reviewPlanTextPath
& $addRunHandoffValue 'Manifest' $manifestPath
& $addRunHandoffValue 'State' $runStatePath
& $addRunHandoffValue 'HTML index' $indexPath
[IO.File]::WriteAllText(
    $runHandoffPath,
    (($runHandoffLines -join "`n") + "`n"),
    $utf8
)

$rows = [Text.StringBuilder]::new()
foreach ($result in $results | Sort-Object Repository) {
    $repository = [Net.WebUtility]::HtmlEncode($result.Repository)
    $sourceKind = [Net.WebUtility]::HtmlEncode($result.SourceKind)
    $status = [Net.WebUtility]::HtmlEncode($result.Status)
    $encodedCommit = [Net.WebUtility]::HtmlEncode([string] $result.Commit)
    $slug = [Net.WebUtility]::HtmlEncode($result.Slug)
    [void] $rows.Append(
        "<tr><td>$repository</td><td>$sourceKind</td><td>$status</td>" +
        "<td><code>$encodedCommit</code></td>" +
        "<td><a href=`"$slug/review.html`">HTML</a> " +
        "<a href=`"$slug/review.md`">Markdown</a> " +
        "<a href=`"$slug/review.txt`">Plain text</a> " +
        "<a href=`"$slug/handoff.md`">Handoff</a></td></tr>"
    )
}
$encodedRunId = [Net.WebUtility]::HtmlEncode($runId)
$encodedRunStatus = [Net.WebUtility]::HtmlEncode($runStatus)
$encodedScope = [Net.WebUtility]::HtmlEncode($scopeName)
$encodedPublicResearch = [Net.WebUtility]::HtmlEncode(
    (Get-StatusWord -Enabled $publicResearchEnabled)
)
$encodedProvenance = [Net.WebUtility]::HtmlEncode(
    (Get-StatusWord -Enabled $provenanceResearchEnabled)
)
$indexHtml = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Repository Review Run</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.45; }
main { max-width: 1200px; margin: 0 auto; padding: 2rem; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: .6rem; border: 1px solid currentColor; text-align: left; vertical-align: top; }
a { color: inherit; }
code { overflow-wrap: anywhere; }
</style>
</head>
<body>
<main>
<h1>Repository Review Run</h1>
<p>Run <code>$encodedRunId</code>; status <strong>$encodedRunStatus</strong>;
scope <strong>$encodedScope</strong>; public research <strong>$encodedPublicResearch</strong>;
provenance <strong>$encodedProvenance</strong>.</p>
<p><a href="review-plan.txt">Review plan (text)</a> ·
<a href="review-plan.json">Review plan (JSON)</a> ·
<a href="handoff.md">Run handoff</a> ·
<a href="state.json">Run state</a> ·
<a href="manifest.json">Manifest</a></p>
<table>
<thead><tr><th>Repository</th><th>Source</th><th>Status</th><th>Commit</th><th>Artifacts</th></tr></thead>
<tbody>$rows</tbody>
</table>
</main>
</body>
</html>
"@
[IO.File]::WriteAllText($indexPath, $indexHtml, $utf8)

$results | Sort-Object Repository |
    Format-Table Repository, SourceKind, Status, ExitCode, Session -AutoSize

Write-Host ''
Write-Host "Run workspace: $runWorkspace"
Write-Host "Run output:    $runResults"
Write-Host "Review plan JSON: $reviewPlanJsonPath"
Write-Host "Review plan text: $reviewPlanTextPath"
Write-Host "Manifest:      $manifestPath"
Write-Host "State:         $runStatePath"
Write-Host "Handoff:       $runHandoffPath"
Write-Host "HTML index:    $indexPath"
Write-Host "RHYOLITE PROGRESS | run | completed | $runStatus; $runResults"
foreach ($failedResult in @($results | Where-Object Status -ne 'Completed')) {
    Write-RhyoliteRepositoryError -Result $failedResult
}

$allowAllMode = $env:COPILOT_ALLOW_ALL -match '^(?i:true|1|yes)$'
$shouldOpenHtml = $OpenHtml -or ($allowAllMode -and -not $NoOpenHtml)
if (-not $shouldOpenHtml -and
    -not $NoOpenHtml -and
    (Test-InteractiveConsole)) {
    $openInput = (Read-Host 'Open the local HTML report index now? [y/N]').Trim()
    $shouldOpenHtml = $openInput -match '^(?i:y|yes)$'
}

if ($shouldOpenHtml) {
    try {
        if ($IsWindows) {
            Start-Process -FilePath $indexPath
        }
        elseif ($IsMacOS) {
            $openPath = Resolve-ApplicationPath -Name 'open'
            $openInfo = [Diagnostics.ProcessStartInfo]::new()
            $openInfo.FileName = $openPath
            $openInfo.UseShellExecute = $false
            $openInfo.ArgumentList.Add($indexPath)
            [void] [Diagnostics.Process]::Start($openInfo)
        }
        else {
            $openPath = Resolve-ApplicationPath -Name 'xdg-open'
            $openInfo = [Diagnostics.ProcessStartInfo]::new()
            $openInfo.FileName = $openPath
            $openInfo.UseShellExecute = $false
            $openInfo.ArgumentList.Add($indexPath)
            [void] [Diagnostics.Process]::Start($openInfo)
        }
    }
    catch {
        Write-Warning (
            "Could not open the HTML index automatically: " +
            $_.Exception.Message
        )
    }
}

if (@($results | Where-Object Status -ne 'Completed').Count -gt 0) {
    exit 1
}
