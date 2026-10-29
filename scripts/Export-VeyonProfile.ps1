<#
.SYNOPSIS
    Exports the current Veyon system configuration or profile to a versioned backup JSON.

.DESCRIPTION
    Exports active Veyon settings using veyon-cli config export to a specified destination,
    or generates a timestamped backup in the backups directory.

.PARAMETER DestinationPath
    Optional custom destination path for the exported backup file.

.PARAMETER ProfileName
    Identifier tag for the backup (default: 'system').

.PARAMETER PassThru
    Outputs the backup file info object to the pipeline.

.EXAMPLE
    .\Export-VeyonProfile.ps1
    .\Export-VeyonProfile.ps1 -DestinationPath "C:\backups\veyon-backup.json"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$DestinationPath,

    [Parameter()]
    [string]$ProfileName = 'system',

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    Write-Error "Veyon CLI executable not found. Please install Veyon first."
    exit 1
}

$baseDir = Split-Path -Parent $PSScriptRoot
$backupsDir = Join-Path -Path $baseDir -ChildPath "config\backups"
if (-not (Test-Path $backupsDir)) {
    New-Item -ItemType Directory -Path $backupsDir -Force | Out-Null
}

if (-not $DestinationPath) {
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $cleanTag = ($ProfileName -replace '[^a-zA-Z0-9_\-]', '')
    $filename = "veyon-backup-$cleanTag-$timestamp.json"
    $DestinationPath = Join-Path -Path $backupsDir -ChildPath $filename
} else {
    $destDir = Split-Path -Parent $DestinationPath
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
}

Write-Verbose "Exporting Veyon configuration to: $DestinationPath"
$res = & $cliPath config export "$DestinationPath" 2>&1 | Out-String

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $DestinationPath)) {
    Write-Error "Failed to export Veyon configuration: $res"
    exit 1
}

$fileItem = Get-Item -Path $DestinationPath
Write-Host "[OK] Configuration backed up to: $($fileItem.FullName) ($($fileItem.Length) bytes)" -ForegroundColor Green

if ($PassThru) {
    return [PSCustomObject]@{
        Success = $true
        BackupPath = $fileItem.FullName
        Timestamp = (Get-Date).ToString("o")
        FileSize = $fileItem.Length
    }
}
exit 0
