Set-StrictMode -Version Latest

$script:EmailPattern = '(?i)(?<![A-Z0-9._%+-])' +
    '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}' +
    '(?![A-Z0-9._%+-])'
$script:TerminalControlPattern = '(?:' +
    '\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|' +
    '\x1B\[[0-?]*[ -/]*[@-~]|' +
    '\x1B[@-_]' +
    ')'
$script:ReportHeaderPattern = 'REPOSITORY.*REVIEW.*REPORT'
$script:CredentialPatterns = @(
    [pscustomobject]@{
        Pattern = '(?i)(https?://)[^/@\s]+:[^/@\s]+@'
        Replacement = '$1[credentials omitted]@'
    }
    [pscustomobject]@{
        Pattern = '(?i)((?:proxy-)?authorization\s*:\s*(?:(?:bearer|basic)\s+)?)\S+'
        Replacement = '$1[credential omitted]'
    }
    [pscustomobject]@{
        Pattern = '(?i)((?:access[_-]?token|api[_-]?key|password|secret|token)\s*[:=]\s*)\S+'
        Replacement = '$1[credential omitted]'
    }
    [pscustomobject]@{
        Pattern = '\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}\b'
        Replacement = '[credential omitted]'
    }
)

function ConvertTo-ReviewPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [switch] $RedactEmails,

        [switch] $RedactCredentials
    )

    $result = $Text -replace "`r`n?", "`n"
    $result = [regex]::Replace(
        $result,
        $script:TerminalControlPattern,
        ''
    )
    if ($RedactCredentials) {
        foreach ($credentialPattern in $script:CredentialPatterns) {
            $result = [regex]::Replace(
                $result,
                $credentialPattern.Pattern,
                $credentialPattern.Replacement
            )
        }
    }
    if ($RedactEmails) {
        $result = [regex]::Replace(
            $result,
            $script:EmailPattern,
            '[email omitted]'
        )
    }

    return $result
}

function Get-ReviewReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Timeline
    )

    $lines = @($Timeline -split "`n")
    $reportStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*={80,}\s*$') {
            continue
        }

        $windowEnd = [Math]::Min($i + 3, $lines.Count - 1)
        if (($lines[$i..$windowEnd] -join ' ') -match
            $script:ReportHeaderPattern) {
            $reportStart = $i
            break
        }
    }

    if ($reportStart -lt 0) {
        return [pscustomobject]@{
            Found = $false
            Text = ''
            ContainsMarkdownTable = $false
            HasClosingDelimiter = $false
        }
    }

    $reportEnd = -1
    for ($i = $lines.Count - 1; $i -ge $reportStart; $i--) {
        if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
            $reportEnd = $i
            break
        }
    }

    $hasClosingDelimiter = $reportEnd -gt $reportStart -and
        $lines[$reportEnd] -match '^\s*={80,}\s*$'

    $reportLines = @(
        $lines[$reportStart..$reportEnd] | ForEach-Object {
            if ($_.StartsWith(' ')) {
                $_.Substring(1)
            }
            else {
                $_
            }
        }
    )

    return [pscustomobject]@{
        Found = $true
        Text = $reportLines -join "`n"
        ContainsMarkdownTable = @(
            $reportLines |
                Where-Object { $_ -match '^\s*\|.*\|\s*$' }
        ).Count -gt 0
        HasClosingDelimiter = $hasClosingDelimiter
    }
}

function ConvertTo-ReviewMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $normalized = ConvertTo-ReviewPlainText -Text $Text
    $indented = @(
        $normalized.TrimEnd() -split "`n" |
            ForEach-Object { "    $_" }
    ) -join "`n"

    return "# Repository Review Report`n`n$indented`n"
}

function ConvertTo-SafeMarkdownDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [AllowEmptyString()]
        [string] $Text = ''
    )

    $safeTitle = $Title -replace '[\r\n]', ' '
    $lines = (ConvertTo-ReviewPlainText -Text $Text) -split "`n"
    $body = @($lines | ForEach-Object { "    $_" }) -join "`n"
    return "# $safeTitle`n`n$body"
}

function ConvertTo-ReviewHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [string] $Repository = '',

        [string] $Commit = '',

        [string] $Status = ''
    )

    $normalized = ConvertTo-ReviewPlainText -Text $Text
    $encodedReport = [Net.WebUtility]::HtmlEncode($normalized.TrimEnd())
    $encodedRepository = [Net.WebUtility]::HtmlEncode($Repository)
    $encodedCommit = [Net.WebUtility]::HtmlEncode($Commit)
    $encodedStatus = [Net.WebUtility]::HtmlEncode($Status)
    $metadata = [Text.StringBuilder]::new()

    foreach ($item in @(
        [pscustomobject]@{
            Label = 'Repository'
            Value = $encodedRepository
        }
        [pscustomobject]@{
            Label = 'Commit'
            Value = $encodedCommit
        }
        [pscustomobject]@{
            Label = 'Status'
            Value = $encodedStatus
        }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($item.Value)) {
            [void] $metadata.Append(
                "<dt>$($item.Label)</dt><dd>$($item.Value)</dd>"
            )
        }
    }

    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Repository Review Report</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.45; }
main { max-width: 1000px; margin: 0 auto; padding: 2rem; }
h1 { margin-top: 0; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: .25rem 1rem; }
dt { font-weight: 700; }
dd { margin: 0; overflow-wrap: anywhere; }
pre { padding: 1rem; border: 1px solid currentColor; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; font: 14px/1.45 ui-monospace, monospace; }
</style>
</head>
<body>
<main>
<h1>Repository Review Report</h1>
<dl>$metadata</dl>
<pre>$encodedReport</pre>
</main>
</body>
</html>
"@
}

function New-ReviewHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Repository,

        [string] $Commit = '',

        [Parameter(Mandatory)]
        [string] $Status,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Session,

        [string] $SessionId = '',

        [string] $SourceKind = 'RemoteUrl',

        [string] $SourcePath = '',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Checkout,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter(Mandatory)]
        [string] $Scope,

        [Parameter(Mandatory)]
        [string] $ScopeEstimate,

        [Parameter(Mandatory)]
        [string] $ProvenanceWindow,

        [Parameter(Mandatory)]
        [Collections.IDictionary] $Artifacts
    )

    $formatValue = {
        param([AllowEmptyString()][string] $Value)
        @(
            (ConvertTo-ReviewPlainText -Text $Value) -split "`n" |
                ForEach-Object { "    $_" }
        ) -join "`n"
    }
    $artifactLines = @(
        foreach ($entry in $Artifacts.GetEnumerator() | Sort-Object Name) {
            "$($entry.Name):`n`n$(& $formatValue ([string] $entry.Value))"
        }
    ) -join "`n`n"
    $continuation = if ([string]::IsNullOrWhiteSpace($SessionId)) {
        @'
Setup did not reach a child Copilot session. Rerun `repository-review` using the
repository URL, requested commit, scope, and output choices recorded in
`state.json`. Do not analyze the verification clone directly.
'@.Trim()
    }
    else {
        @"
The saved Copilot session ID is ``$SessionId``. Do not invoke
``copilot --resume`` directly: a direct resume does not reliably restore this
review's path, tool, network, and environment restrictions. Start the
``repository-review`` agent and provide this handoff path so a trusted runner
can establish a restricted continuation.
"@.Trim()
    }

    return @"
# Repository review handoff

Repository:

$(& $formatValue $Repository)

Source kind:

$(& $formatValue $SourceKind)

Selected source path:

$(& $formatValue $SourcePath)

Commit:

$(& $formatValue $Commit)

Status:

$(& $formatValue $Status)

Scope:

$(& $formatValue $Scope)

Planning estimate:

$(& $formatValue $ScopeEstimate)

Provenance window:

$(& $formatValue $ProvenanceWindow)

Read-only checkout:

$(& $formatValue $Checkout)

Writable output directory:

$(& $formatValue $OutputDirectory)

Copilot session:

$(& $formatValue $Session)

Copilot session ID:

$(& $formatValue $SessionId)

## Continue safely

$continuation

Read ``state.json``, ``request.txt``, and ``errors.txt`` before resuming. The checkout
must remain read-only; write new or updated artifacts only in the output
directory.

## Artifacts

$artifactLines
"@
}

Export-ModuleMember -Function @(
    'ConvertTo-ReviewPlainText'
    'Get-ReviewReport'
    'ConvertTo-ReviewMarkdown'
    'ConvertTo-SafeMarkdownDocument'
    'ConvertTo-ReviewHtml'
    'New-ReviewHandoff'
)
