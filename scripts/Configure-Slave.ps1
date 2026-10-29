<#
.SYNOPSIS
    Configures the current machine as a Veyon Slave (Student/Client) computer.

.DESCRIPTION
    Automates complete setup for Veyon Slave:
    - Backs up current configuration prior to modifications.
    - Security Audit: Purges any private keys found on the client machine.
    - Imports Master's public key only.
    - Imports Slave configuration JSON profile.
    - Enables Windows Software SAS and firewall exceptions.
    - Configures VeyonService for Automatic start and launches the service.
    - Runs security validation to guarantee private key isolation.

.PARAMETER KeyName
    Authentication key identifier (default: 'teacher').

.PARAMETER PublicKeyPath
    Path to the Master public key file (.pem).

.PARAMETER ConfigFile
    Path to custom Slave JSON configuration file.

.PARAMETER HideTrayIcon
    Configures the service to hide the tray icon on the student desktop.

.PARAMETER SkipServiceRestart
    Do not restart Veyon Service.

.PARAMETER Elevate
    Auto-prompts for UAC elevation if running non-elevated.

.PARAMETER Force
    Overwrites existing public key without prompting.

.PARAMETER JsonOutput
    Outputs results strictly as JSON.

.EXAMPLE
    .\Configure-Slave.ps1 -PublicKeyPath "\\master-pc\share\teacher_public_key.pem"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [string]$PublicKeyPath,

    [Parameter()]
    [string]$ConfigFile,

    [Parameter()]
    [switch]$HideTrayIcon,

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
        if ($PublicKeyPath) { $argList += @("-PublicKeyPath", "`"$PublicKeyPath`"") }
        if ($ConfigFile) { $argList += @("-ConfigFile", "`"$ConfigFile`"") }
        if ($HideTrayIcon) { $argList += "-HideTrayIcon" }
        if ($SkipServiceRestart) { $argList += "-SkipServiceRestart" }
        if ($Force) { $argList += "-Force" }
        if ($JsonOutput) { $argList += "-JsonOutput" }

        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    } else {
        Write-Error "Administrator privileges are required to configure Veyon Slave. Reopen PowerShell as Administrator or pass -Elevate."
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
        $bkObj = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backupScript -ProfileName "pre-slave-setup" -PassThru
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
    Write-Error "Veyon CLI executable not found. Please install Veyon client first."
    exit 1
}

# 3. CRITICAL SECURITY CHECK: Purge Private Keys on Slave
$kOut = & $cliPath authkeys list 2>&1 | Out-String
foreach ($l in ($kOut -split "`r?`n")) {
    $t = $l.Trim()
    if ($t -match '/private$') {
        Write-Warning "SECURITY AUDIT: Private key detected on Slave PC ($t)! Purging immediately for security..."
        & $cliPath authkeys delete $t
    }
}

# 4. Import Public Key
$pubKeyId = "$KeyName/public"
$resolvedPubKey = $null

if ($PublicKeyPath) {
    if (Test-Path $PublicKeyPath) {
        $resolvedPubKey = (Resolve-Path $PublicKeyPath).Path
    } else {
        Write-Error "Specified public key path not found: $PublicKeyPath"
        exit 1
    }
} else {
    # Check default search paths
    $cands = @(
        (Join-Path -Path $keysDir -ChildPath "${KeyName}_public_key.pem"),
        (Join-Path -Path $keysDir -ChildPath "teacher_public_key.pem"),
        (Join-Path -Path $keysDir -ChildPath "default_public_key.pem")
    )
    foreach ($c in $cands) {
        if (Test-Path $c) { $resolvedPubKey = $c; break }
    }
}

if ($resolvedPubKey) {
    Write-Host "Importing Master public key from $resolvedPubKey..." -ForegroundColor Cyan
    & $cliPath authkeys import $pubKeyId "$resolvedPubKey"
} else {
    Write-Warning "No public key file provided. Authentication requires importing the Master's public key."
}

# 5. Import Slave Configuration Profile
$targetConfig = if ($ConfigFile) {
    $ConfigFile
} else {
    Join-Path -Path $configDir -ChildPath "veyon-slave.json"
}

if (-not (Test-Path $targetConfig)) {
    Write-Error "Slave configuration profile not found: $targetConfig"
    exit 1
}

# Handle HideTrayIcon override
$tempConfig = $null
if ($HideTrayIcon) {
    $jsonObj = Get-Content -Path $targetConfig -Raw | ConvertFrom-Json
    if ($jsonObj.Service) { $jsonObj.Service.HideTrayIcon = "true" }
    $tempConfig = Join-Path -Path $env:TEMP -ChildPath "veyon-slave-override-$([System.Guid]::NewGuid().ToString('N')).json"
    $jsonObj | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfig -Encoding UTF8
    $targetConfig = $tempConfig
}

Write-Host "Applying Slave configuration from: $targetConfig" -ForegroundColor Cyan
$impRes = & $cliPath config import "$targetConfig" 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed importing configuration: $impRes"
    exit 1
}

if ($tempConfig -and (Test-Path $tempConfig)) { Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue }

# Enforce mandatory system settings
& $cliPath config set Authentication/Method 1
& $cliPath config set Windows/SoftwareSASEnabled 1
& $cliPath config set Service/SoftwareSASEnabled 0
& $cliPath config set Network/FirewallExceptionEnabled 1
& $cliPath config set Service/Autostart true

# Disable ForceGuest in Windows Registry
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "ForceGuest" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# 6. Service Registration & Start
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
$validateScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Slave.ps1"
$valResult = $null
if (Test-Path $validateScript) {
    $valResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validateScript -KeyName $KeyName -JsonOutput | ConvertFrom-Json
}

$output = [PSCustomObject]@{
    Role = "Slave"
    Success = if ($valResult) { $valResult.Success } else { $true }
    BackupFile = $backupFile
    Validation = $valResult
    Timestamp = (Get-Date).ToString("o")
}

if ($JsonOutput) {
    return ($output | ConvertTo-Json -Depth 5)
} else {
    Write-Host "`n[SUCCESS] Slave Auto-Configuration completed successfully!" -ForegroundColor Green
    exit 0
}
