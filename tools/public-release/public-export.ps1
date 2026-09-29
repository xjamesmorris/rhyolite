[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$powerShellCommand = if ($PSVersionTable.PSEdition -eq 'Core') {
    'pwsh'
} else {
    'powershell'
}

& node (Join-Path $scriptDir 'public-release.mjs') `
    'export' '--shell' 'powershell' '--powershell-command' $powerShellCommand `
    @Arguments
exit $LASTEXITCODE
