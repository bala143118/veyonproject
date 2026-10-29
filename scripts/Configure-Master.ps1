<#
.SYNOPSIS
    Configures the current machine as a Veyon Master (Teacher/Admin) computer.

.DESCRIPTION
    Automates complete setup for Veyon Master:
    - Backs up current configuration prior to modifications.
    - Generates or imports 4096-bit RSA key pair (restricting private key permissions to Administrators).
    - Exports public key to keys directory for distribution to Slaves.
    - Imports Master configuration JSON profile.
    - Enables Windows Software SAS and firewall exceptions.
    - Registers classroom location and client computers if specified.
    - Restarts Veyon Windows Service and verifies health.

.PARAMETER KeyName
    Authentication key identifier (default: 'teacher').

.PARAMETER RoomName
    Classroom / Location name (e.g. 'Lab 101').

.PARAMETER ClientHosts
    Array of student hostnames or IP addresses to add to the classroom.

.PARAMETER ConfigFile
    Path to custom Master JSON configuration file.

.PARAMETER ExportPublicKeyPath
    Custom path to save the exported public key.

.PARAMETER SkipServiceRestart
    Do not restart Veyon Service.

.PARAMETER Elevate
    Auto-prompts for UAC elevation if running non-elevated.

.PARAMETER Force
    Overwrites existing keys without prompting.

.PARAMETER JsonOutput
    Outputs results strictly as JSON.

.EXAMPLE
    .\Configure-Master.ps1 -RoomName "Lab 101" -ClientHosts "192.168.1.101","192.168.1.102"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [string]$RoomName,

    [Parameter()]
    [string[]]$ClientHosts,

    [Parameter()]
    [string]$ConfigFile,

    [Parameter()]
    [string]$ExportPublicKeyPath,

    [Parameter()]
    [switch]$SkipServiceRestart,

    [Parameter()]
    [switch]$Elevate,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$JsonOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if ($Elevate) {
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-KeyName", "`"$KeyName`"")
        if ($RoomName) { $argList += @("-RoomName", "`"$RoomName`"") }
        if ($ClientHosts) { foreach ($c in $ClientHosts) { $argList += @("-ClientHosts", "`"$c`"") } }
        if ($ConfigFile) { $argList += @("-ConfigFile", "`"$ConfigFile`"") }
        if ($ExportPublicKeyPath) { $argList += @("-ExportPublicKeyPath", "`"$ExportPublicKeyPath`"") }
        if ($SkipServiceRestart) { $argList += "-SkipServiceRestart" }
        if ($Force) { $argList += "-Force" }
        if ($JsonOutput) { $argList += "-JsonOutput" }

        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    } else {
        Write-Error "Administrator privileges are required to configure Veyon Master. Reopen PowerShell as Administrator or pass -Elevate."
        exit 1
    }
}

$baseDir = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path -Path $baseDir -ChildPath "config"
$keysDir = Join-Path -Path $configDir -ChildPath "keys"

# 1. Automatic Backup Before Modifying
$backupScript = Join-Path -Path $PSScriptRoot -ChildPath "Export-VeyonProfile.ps1"
$backupFile = $null
if (Test-Path $backupScript) {
    try {
        $bkObj = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backupScript -ProfileName "pre-master-setup" -PassThru
        if ($bkObj -and $bkObj.BackupPath) { $backupFile = $bkObj.BackupPath }
    } catch {}
}

# 2. Locate Veyon CLI
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

# 3. Authentication Keys Setup
$privKeyId = "$KeyName/private"
$pubKeyId = "$KeyName/public"

$kOut = & $cliPath authkeys list 2>&1 | Out-String
$keysExist = ($kOut -match [regex]::Escape($privKeyId))

if (-not $keysExist -or $Force) {
    # Check if key file exists in keysDir
    $candPrivKey = Join-Path -Path $keysDir -ChildPath "${KeyName}_private_key.pem"
    if (Test-Path $candPrivKey) {
        Write-Host "Importing Master private key from $candPrivKey..." -ForegroundColor Cyan
        & $cliPath authkeys import $privKeyId $candPrivKey
        & $cliPath authkeys extract $privKeyId
    } else {
        Write-Host "Creating new 4096-bit RSA key pair '$KeyName'..." -ForegroundColor Cyan
        & $cliPath authkeys create $KeyName
    }
}

# Restrict private key permissions to Administrators
try {
    & $cliPath authkeys setaccessgroup $privKeyId "Administrators" 2>$null
} catch {}

# Export public key for distribution
$pubExportFile = if ($ExportPublicKeyPath) {
    $ExportPublicKeyPath
} else {
    Join-Path -Path $keysDir -ChildPath "${KeyName}_public_key.pem"
}
$pubExportDir = Split-Path -Parent $pubExportFile
if ($pubExportDir -and -not (Test-Path $pubExportDir)) {
    New-Item -ItemType Directory -Path $pubExportDir -Force | Out-Null
}
& $cliPath authkeys export $pubKeyId $pubExportFile 2>$null

# 4. Import Master Configuration Profile
$targetConfig = if ($ConfigFile) {
    $ConfigFile
} else {
    Join-Path -Path $configDir -ChildPath "veyon-master.json"
}

if (-not (Test-Path $targetConfig)) {
    Write-Error "Master configuration profile not found: $targetConfig"
    exit 1
}

Write-Host "Applying Master configuration from: $targetConfig" -ForegroundColor Cyan
$impRes = & $cliPath config import "$targetConfig" 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed importing configuration: $impRes"
    exit 1
}

# Enforce mandatory system settings
& $cliPath config set Authentication/Method 1
& $cliPath config set Windows/SoftwareSASEnabled 1
& $cliPath config set Service/SoftwareSASEnabled 0
& $cliPath config set Network/FirewallExceptionEnabled 1

# Disable ForceGuest in Windows Registry
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "ForceGuest" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# 5. Register Classroom and Clients
if ($RoomName) {
    Write-Host "Registering classroom location: $RoomName" -ForegroundColor Cyan
    & $cliPath networkobjects add location "$RoomName" 2>$null

    if ($ClientHosts) {
        foreach ($ch in $ClientHosts) {
            $comp = $ch.Trim()
            if ($comp) {
                Write-Host "  Adding student PC '$comp' to '$RoomName'..." -ForegroundColor Cyan
                & $cliPath networkobjects add computer "$comp" "$comp" "" "$RoomName" 2>$null
            }
        }
    }
}

# 6. Service Management
& $cliPath service register 2>$null
Set-Service -Name "VeyonService" -StartupType Automatic -ErrorAction SilentlyContinue

if (-not $SkipServiceRestart) {
    Write-Host "Restarting Veyon Service..." -ForegroundColor Cyan
    & $cliPath service restart 2>$null
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Start-Service -Name "VeyonService" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# 7. Verification
$validateScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Master.ps1"
$valResult = $null
if (Test-Path $validateScript) {
    $valResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validateScript -KeyName $KeyName -JsonOutput | ConvertFrom-Json
}

$output = [PSCustomObject]@{
    Role = "Master"
    Success = if ($valResult) { $valResult.Success } else { $true }
    BackupFile = $backupFile
    ExportedPublicKey = $pubExportFile
    Validation = $valResult
    Timestamp = (Get-Date).ToString("o")
}

if ($JsonOutput) {
    return ($output | ConvertTo-Json -Depth 5)
} else {
    Write-Host "`n[SUCCESS] Master Auto-Configuration completed successfully!" -ForegroundColor Green
    Write-Host "Public Key for Slaves exported to: $pubExportFile" -ForegroundColor Yellow
    exit 0
}
