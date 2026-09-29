[CmdletBinding()]
param(
    [switch] $RunAgentSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$rootLauncherPath = Join-Path $root 'rhyolite'
$testRoot = Join-Path $root '.test-output\install-test'
$copilotHome = Join-Path $testRoot 'copilot-home'

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null

$previousCopilotHome = $env:COPILOT_HOME
$env:COPILOT_HOME = $copilotHome

try {
    if (-not (Test-Path -LiteralPath $rootLauncherPath -PathType Leaf)) {
        throw 'Repository checkout is missing the root rhyolite launcher.'
    }

    $marketplaceOutput = & copilot plugin marketplace add $root 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Marketplace registration failed: $marketplaceOutput"
    }

    $installOutput = & copilot plugin install `
        'rhyolite@rhyolite-tools' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Plugin installation failed: $installOutput"
    }

    $listOutput = (& copilot plugin list 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or
        -not $listOutput.Contains(
            'rhyolite@rhyolite-tools'
        )) {
        throw "Installed plugin was not listed: $listOutput"
    }
    $installedStartCommand = @(
        Get-ChildItem -LiteralPath $copilotHome -Recurse -File `
            -Filter 'start.md' |
            Where-Object {
                $_.FullName -match '[\\/]installed-plugins[\\/]' -and
                [IO.File]::ReadAllText($_.FullName).Contains(
                    'RHYOLITE_START_COMMAND_V1'
                )
            }
    )
    $installedPluginRoot = $null
    if ($installedStartCommand.Count -eq 1) {
        $installedPluginRoot = Split-Path -Parent (
            Split-Path -Parent $installedStartCommand[0].FullName
        )
    }
    elseif (
        $installedStartCommand.Count -eq 0 -and
        $listOutput.Contains(
            'Live Plugins (loaded from a local marketplace directory, never copied)'
        ) -and
        $listOutput.Contains("from $root")
    ) {
        $installedPluginRoot = Join-Path $root 'plugins\rhyolite'
        $liveStartCommand = Join-Path $installedPluginRoot 'commands\start.md'
        if (
            -not (Test-Path -LiteralPath $liveStartCommand -PathType Leaf) -or
            -not [IO.File]::ReadAllText($liveStartCommand).Contains(
                'RHYOLITE_START_COMMAND_V1'
            )
        ) {
            throw (
                'Live-installed plugin does not contain the discoverable ' +
                '/rhyolite:start command marker.'
            )
        }
        $installedStartCommand = @(Get-Item -LiteralPath $liveStartCommand)
    }
    else {
        throw (
            'Installed plugin does not contain exactly one discoverable ' +
            '/rhyolite:start command marker.'
        )
    }
    foreach ($launcherRelativePath in @(
        'bin\rhyolite'
        'bin\rhyolite.ps1'
    )) {
        if (-not (Test-Path -LiteralPath (
            Join-Path $installedPluginRoot $launcherRelativePath
        ) -PathType Leaf)) {
            throw "Installed plugin is missing launcher: $launcherRelativePath"
        }
    }
    if (Test-Path -LiteralPath (
        Join-Path $installedPluginRoot 'rhyolite'
    )) {
        throw 'Installed plugin incorrectly contains the repository-root launcher.'
    }
    foreach ($developmentAgentName in @(
        'rhyolite-ui-validator.agent.md'
        'rhyolite-tui-runtime-validator.agent.md'
    )) {
        if (Test-Path -LiteralPath (
            Join-Path $installedPluginRoot "agents\$developmentAgentName"
        )) {
            throw (
                'Installed plugin contains repository-only validator agent: ' +
                $developmentAgentName
            )
        }
    }

    if ($RunAgentSmoke) {
        $response = (& copilot `
            -C $root `
            --agent 'rhyolite:repo-review' `
            --prompt (
                'Without inspecting or modifying files, reply with exactly ' +
                'RHYOLITE_READY.'
            ) `
            --silent `
            --no-color `
            --no-ask-user `
            --no-custom-instructions `
            --available-tools view 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or
            $response.Trim() -ne 'RHYOLITE_READY') {
            throw "Agent smoke test failed: $response"
        }

        $commandResponse = (& copilot `
            -C $root `
            --prompt (
                '/rhyolite:start ' +
                'https://github.com/octocat/Hello-World'
            ) `
            --silent `
            --no-color `
            --no-ask-user `
            --no-custom-instructions `
            --available-tools view `
            --allow-all-tools 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or
            $commandResponse.Contains('Unknown slash command') -or
            $commandResponse.Contains('Unknown command') -or
            -not $commandResponse.Contains('Rhyolite')) {
            throw "Namespaced start-command smoke test failed: $commandResponse"
        }
    }
}
finally {
    if ($null -eq $previousCopilotHome) {
        Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:COPILOT_HOME = $previousCopilotHome
    }
}

Write-Output 'Plugin marketplace installation test passed.'
