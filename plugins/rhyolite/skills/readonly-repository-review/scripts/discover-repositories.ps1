[CmdletBinding()]
param(
    [string] $Root = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PhysicalDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) {
        throw "Discovery root is not a directory: $Path"
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $item = $item.ResolveLinkTarget($true)
    }

    return [IO.Path]::GetFullPath($item.FullName)
}

function Test-GitWorktreeMarker {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return Test-Path -LiteralPath (Join-Path $Path '.git')
}

function Assert-ControlFreePath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path -match '[\x00-\x1F\x7F]') {
        throw "Repository discovery path contains control characters: $Path"
    }
}

$rootPath = Resolve-PhysicalDirectory -Path $Root
Assert-ControlFreePath -Path $rootPath

$cursor = $rootPath
while ($true) {
    if (Test-GitWorktreeMarker -Path $cursor) {
        Write-Output "current`t$cursor"
        exit 0
    }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) {
        break
    }
    $cursor = $parent
}

Get-ChildItem -LiteralPath $rootPath -Directory -Force |
    Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
        (Test-GitWorktreeMarker -Path $_.FullName)
    } |
    Sort-Object Name |
    ForEach-Object {
        $path = [IO.Path]::GetFullPath($_.FullName)
        Assert-ControlFreePath -Path $path
        Write-Output "child`t$path"
    }
