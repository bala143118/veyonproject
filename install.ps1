<#
.SYNOPSIS
    Single-command setup entry point for Veyon Master or Slave.

.DESCRIPTION
    One-command setup for VEYON OPS platform:
    .\install.ps1 -Role Master
    .\install.ps1 -Role Slave

.PARAMETER Role
    Target role: 'Master' or 'Slave'.

.PARAMETER KeyName
    Authentication key name (default: 'teacher').

.PARAMETER PublicKeyPath
    Path to Master public key (required on Slave if not in default location).

.PARAMETER RoomName
    (Master) Classroom location name.

.PARAMETER ClientHosts
    (Master) List of student hostnames or IPs.

.PARAMETER Elevate
    Auto-prompts for UAC elevation if running non-elevated.

.PARAMETER Force
    Overwrites existing keys without prompting.

.EXAMPLE
    .\install.ps1 -Role Master
    .\install.ps1 -Role Slave -PublicKeyPath "\\master\keys\teacher_public_key.pem"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet('Master', 'Slave')]
    [string]$Role,

    [Parameter()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [string]$PublicKeyPath,

    [Parameter()]
    [string]$RoomName,

    [Parameter()]
    [string[]]$ClientHosts,

    [Parameter()]
    [switch]$HideTrayIcon,

    [Parameter()]
    [switch]$Elevate,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         VEYON OPS -- ONE-COMMAND SETUP                   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not $Role) {
    Write-Host "No role specified. Usage:" -ForegroundColor Yellow
    Write-Host "  .\install.ps1 -Role Master [-RoomName <name>] [-ClientHosts <hosts>]" -ForegroundColor White
    Write-Host "  .\install.ps1 -Role Slave  [-PublicKeyPath <path>]" -ForegroundColor White
    Write-Host "`nTo start the web dashboard instead, run:" -ForegroundColor DarkGray
    Write-Host "  .\start-dashboard.ps1" -ForegroundColor DarkGray
    exit 1
}

$scriptDir = Join-Path -Path $PSScriptRoot -ChildPath "scripts"

if ($Role -eq 'Master') {
    $targetScript = Join-Path -Path $scriptDir -ChildPath "Configure-Master.ps1"
    $params = @{
        KeyName = $KeyName
    }
    if ($RoomName) { $params['RoomName'] = $RoomName }
    if ($ClientHosts) { $params['ClientHosts'] = $ClientHosts }
    if ($Elevate) { $params['Elevate'] = $true }
    if ($Force) { $params['Force'] = $true }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScript @params
    exit $LASTEXITCODE

} elseif ($Role -eq 'Slave') {
    $targetScript = Join-Path -Path $scriptDir -ChildPath "Configure-Slave.ps1"
    $params = @{
        KeyName = $KeyName
    }
    if ($PublicKeyPath) { $params['PublicKeyPath'] = $PublicKeyPath }
    if ($HideTrayIcon) { $params['HideTrayIcon'] = $true }
    if ($Elevate) { $params['Elevate'] = $true }
    if ($Force) { $params['Force'] = $true }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScript @params
    exit $LASTEXITCODE
}
