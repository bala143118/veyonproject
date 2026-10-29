<#
.SYNOPSIS
    Restores a previously exported Veyon configuration backup.

.DESCRIPTION
    Validates a target JSON backup file, creates a safety pre-restore snapshot of the current configuration,
    imports the settings into Veyon, and restarts the Veyon service. Requires Administrator privileges.

.PARAMETER BackupFile
    Path to the JSON backup file to restore.

.PARAMETER NoPreBackup
    Skips creating an automatic snapshot before restoring.

.PARAMETER SkipServiceRestart
    Do not restart the Veyon Windows Service after restoring.

.EXAMPLE
    .\Restore-VeyonBackup.ps1 -BackupFile "config\backups\veyon-backup-system-20261028-120000.json"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BackupFile,

    [Parameter()]
    [switch]$NoPreBackup,

    [Parameter()]
    [switch]$SkipServiceRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Error "Administrator privileges are required to restore Veyon configuration."
    exit 1
}

if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file not found at: $BackupFile"
    exit 1
}

# Validate JSON
try {
    $jsonObj = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
    Write-Host "[OK] Backup JSON syntax verified." -ForegroundColor Green
} catch {
    Write-Error "Invalid JSON in backup file: $_"
    exit 1
}

function Find-VeyonCli {
    $candidates = @(
        "C:\Program Files\Veyon\veyon-cli.exe",
        "C:\Program Files (x86)\Veyon\veyon-cli.exe",
        "C:\Program Files\Veyon\veyon-wcli.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $inPath = Get-Command "veyon-cli.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    return $null
}

$cliPath = Find-VeyonCli
if (-not $cliPath) {
    Write-Error "Veyon CLI executable not found."
    exit 1
}

# Pre-restore safety backup
if (-not $NoPreBackup) {
    $exportScript = Join-Path -Path $PSScriptRoot -ChildPath "Export-VeyonProfile.ps1"
    if (Test-Path $exportScript) {
        Write-Host "Creating safety pre-restore backup..." -ForegroundColor Yellow
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exportScript -ProfileName "pre-restore-safety"
    }
}

# Import configuration
Write-Host "Applying restored configuration from: $BackupFile" -ForegroundColor Cyan
$res = & $cliPath config import "$BackupFile" 2>&1 | Out-String

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to import configuration: $res"
    exit 1
}
Write-Host "[OK] Configuration imported successfully." -ForegroundColor Green

# Restart service
if (-not $SkipServiceRestart) {
    Write-Host "Restarting Veyon Service..." -ForegroundColor Cyan
    & $cliPath service restart 2>$null
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Write-Host "[OK] Veyon Service is Running." -ForegroundColor Green
    } else {
        Write-Warning "Veyon Service status: $($svc.Status)"
    }
}

Write-Host "[SUCCESS] Restoration complete." -ForegroundColor Green
exit 0
