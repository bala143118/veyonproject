<#
.SYNOPSIS
    Starts the VEYON OPS Administration Dashboard from root repository.

.DESCRIPTION
    Launches the web administration dashboard on http://127.0.0.1:5000.
    Checks Python 3 and dependencies.

.PARAMETER Port
    Port number to listen on (default: 5000).

.PARAMETER NoBrowser
    Do not automatically launch web browser.

.EXAMPLE
    .\start-dashboard.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port = 5000,

    [Parameter()]
    [switch]$NoBrowser
)

$dashboardLauncher = Join-Path -Path $PSScriptRoot -ChildPath "dashboard\run_dashboard.ps1"
if (-not (Test-Path $dashboardLauncher)) {
    Write-Error "Dashboard launcher not found at: $dashboardLauncher"
    exit 1
}

$params = @{
    Port = $Port
}
if ($NoBrowser) { $params['NoBrowser'] = $true }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dashboardLauncher @params
exit $LASTEXITCODE
