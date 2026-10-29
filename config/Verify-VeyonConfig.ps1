<#
.SYNOPSIS
    Verifies Veyon Master or Slave configuration, security, service, and network settings.

.DESCRIPTION
    Inspects the local system for Veyon installation, CLI tools, configuration values,
    authentication keys (verifying private key is present on Master, absent on Slave),
    Windows service status, and firewall exceptions.

.PARAMETER Role
    The role to verify: 'Master', 'Slave', or 'Auto' (auto-detected based on installed keys/configuration).

.PARAMETER KeyName
    The authentication key pair name (default: 'teacher').

.PARAMETER VeyonBinDir
    Optional custom path to the Veyon binary directory.

.EXAMPLE
    .\Verify-VeyonConfig.ps1 -Role Master
    .\Verify-VeyonConfig.ps1 -Role Slave
    .\Verify-VeyonConfig.ps1 -Role Auto
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Master', 'Slave', 'Auto')]
    [string]$Role = 'Auto',

    [Parameter()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [string]$VeyonBinDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-CheckPass([string]$message) {
    Write-Host "  [PASS] $message" -ForegroundColor Green
}

function Write-CheckFail([string]$message) {
    Write-Host "  [FAIL] $message" -ForegroundColor Red
}

function Write-CheckWarn([string]$message) {
    Write-Host "  [WARN] $message" -ForegroundColor Yellow
}

function Write-CheckInfo([string]$message) {
    Write-Host "  [INFO] $message" -ForegroundColor Cyan
}

$TotalChecks = 0
$PassedChecks = 0
$FailedChecks = 0
$WarningChecks = 0

function Record-Result([bool]$Passed, [string]$PassMsg, [string]$FailMsg, [bool]$IsWarning = $false) {
    $script:TotalChecks++
    if ($Passed) {
        $script:PassedChecks++
        Write-CheckPass $PassMsg
    } elseif ($IsWarning) {
        $script:WarningChecks++
        Write-CheckWarn $FailMsg
    } else {
        $script:FailedChecks++
        Write-CheckFail $FailMsg
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       Veyon Configuration & Security Verifier           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Locate Veyon CLI
$cliPath = $null
$installDir = $null

$searchPaths = @()
if ($VeyonBinDir) { $searchPaths += $VeyonBinDir }
$searchPaths += @(
    "C:\Program Files\Veyon",
    "C:\Program Files (x86)\Veyon"
)

# Registry search
try {
    $regApp = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\veyon-master.exe" -ErrorAction SilentlyContinue
    if ($regApp -and $regApp.'(default)') {
        $searchPaths += (Split-Path -Parent $regApp.'(default)')
    }
} catch {}

try {
    $regInst = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Veyon" -ErrorAction SilentlyContinue
    if ($regInst -and $regInst.InstallLocation) {
        $searchPaths += $regInst.InstallLocation
    }
} catch {}

foreach ($dir in $searchPaths) {
    if ($dir -and (Test-Path -Path $dir)) {
        $candidate = Join-Path -Path $dir -ChildPath "veyon-cli.exe"
        if (Test-Path -Path $candidate) {
            $cliPath = $candidate
            $installDir = $dir
            break
        }
        $candidateW = Join-Path -Path $dir -ChildPath "veyon-wcli.exe"
        if (Test-Path -Path $candidateW) {
            $cliPath = $candidateW
            $installDir = $dir
            break
        }
    }
}

if (-not $cliPath) {
    $cmd = Get-Command "veyon-cli.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        $cliPath = $cmd.Source
        $installDir = Split-Path -Parent $cmd.Source
    }
}

Record-Result ($null -ne $cliPath) "Veyon CLI detected at: $cliPath" "Veyon CLI executable not found!"
if (-not $cliPath) {
    Write-CheckFail "Cannot proceed with verification without Veyon CLI. Please install Veyon."
    exit 1
}

# 2. Check Supported CLI Modules
$helpText = & $cliPath help 2>&1 | Out-String
$hasAuthKeys = $helpText -match "authkeys"
$hasConfig = $helpText -match "config"
$hasService = $helpText -match "service"
$hasNetObjects = $helpText -match "networkobjects"

Record-Result $hasConfig "CLI module 'config' is supported" "CLI module 'config' is missing"
Record-Result $hasAuthKeys "CLI module 'authkeys' is supported" "CLI module 'authkeys' is missing"
Record-Result $hasService "CLI module 'service' is supported" "CLI module 'service' is missing"

# 3. Read Authentication Keys
$keysOutput = & $cliPath authkeys list 2>&1
$installedKeys = @()
if ($keysOutput) {
    foreach ($line in ($keysOutput -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not ($trimmed.StartsWith("[") -or $trimmed.StartsWith("Available"))) {
            $installedKeys += $trimmed
        }
    }
}

Write-CheckInfo "Installed authentication keys: $(($installedKeys -join ', '))"

# Determine role if Auto
$hasPrivateKey = ($installedKeys -contains "$KeyName/private") -or ($installedKeys -like "*/private")
$hasPublicKey = ($installedKeys -contains "$KeyName/public") -or ($installedKeys -like "*/public")

if ($Role -eq 'Auto') {
    if ($hasPrivateKey) {
        $Role = 'Master'
        Write-CheckInfo "Auto-detected Role: Master (private key is present)"
    } elseif ($hasPublicKey) {
        $Role = 'Slave'
        Write-CheckInfo "Auto-detected Role: Slave (public key is present, private key is absent)"
    } else {
        $Role = 'Slave'
        Write-CheckWarn "No keys found. Defaulting target verification to Slave."
    }
}

Write-Host "`n--- Checking Authentication Security (Role: $Role) ---" -ForegroundColor Yellow
if ($Role -eq 'Master') {
    Record-Result $hasPrivateKey "Master private key ($KeyName/private) is present" "Master private key ($KeyName/private) is missing!"
    Record-Result $hasPublicKey "Master public key ($KeyName/public) is present" "Master public key ($KeyName/public) is missing!"
} else {
    # Slave: Public key MUST be present, Private key MUST NOT be present!
    Record-Result $hasPublicKey "Slave public key ($KeyName/public) is present" "Slave public key ($KeyName/public) is missing! Slave cannot authenticate master connections."
    Record-Result (-not $hasPrivateKey) "Slave security verified: NO private keys installed" "SECURITY VIOLATION: Private key found on Slave ($($installedKeys -match 'private' -join ', '))! Private keys must be removed from student PCs."
}

# 4. Check Core Configuration Values
Write-Host "`n--- Checking Configuration Parameters ---" -ForegroundColor Yellow
function Get-VeyonConfigValue([string]$key) {
    try {
        $res = & $cliPath config get $key 2>$null
        foreach ($l in ($res -split "`r?`n")) {
            $t = $l.Trim()
            if ($t -and -not ($t.StartsWith("[") -or $t.StartsWith("Available"))) {
                return $t
            }
        }
    } catch {}
    return $null
}

$authMethod = Get-VeyonConfigValue "Authentication/Method"
Record-Result ($authMethod -eq "1") "Authentication Method is Key File Authentication (Method = 1)" "Authentication Method is not Key File (Current: '$authMethod', Expected: '1')"

$sasEnabled = Get-VeyonConfigValue "Windows/SoftwareSASEnabled"
Record-Result ($sasEnabled -eq "1") "Windows Software SAS is enabled (SoftwareSASEnabled = 1)" "Windows Software SAS is not enabled (Current: '$sasEnabled', Expected: '1')" $true

$fwEnabled = Get-VeyonConfigValue "Network/FirewallExceptionEnabled"
Record-Result ($fwEnabled -eq "1") "Firewall exceptions setting is enabled (FirewallExceptionEnabled = 1)" "Firewall exceptions setting is disabled or unset (Current: '$fwEnabled')" $true

$serverPort = Get-VeyonConfigValue "Network/VeyonServerPort"
Record-Result ($serverPort -eq "11100" -or -not $serverPort) "Veyon Server port is standard (11100)" "Veyon Server port is non-standard: $serverPort" $true

# 5. Check Service Status
Write-Host "`n--- Checking Veyon Windows Service ---" -ForegroundColor Yellow
$svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
Record-Result ($null -ne $svc) "VeyonService is installed in Windows Service Control Manager" "VeyonService is NOT registered with Windows SCM!"

if ($svc) {
    $isRunning = ($svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)
    Record-Result $isRunning "VeyonService is Running" "VeyonService is not running (Status: $($svc.Status))"

    $cim = Get-CimInstance Win32_Service -Filter "Name='VeyonService'" -ErrorAction SilentlyContinue
    if ($cim) {
        $isAuto = ($cim.StartMode -eq 'Auto')
        Record-Result $isAuto "VeyonService StartMode is Automatic" "VeyonService StartMode is $($cim.StartMode) (Expected: Auto)" $true
    }
}

# 6. Check Windows Defender Firewall
Write-Host "`n--- Checking Windows Firewall Exceptions ---" -ForegroundColor Yellow
try {
    $fwRules = Get-NetFirewallRule -DisplayName "*Veyon*" -ErrorAction SilentlyContinue
    $hasFw = ($null -ne $fwRules -and $fwRules.Count -gt 0)
    Record-Result $hasFw "Windows Defender Firewall rules for Veyon found ($($fwRules.Count) rules)" "No Windows Defender Firewall rules found for Veyon" $true
} catch {
    Write-CheckInfo "NetSecurity module not available or insufficient rights to query firewall rules."
}

# 7. Check Master Network Objects (if Master)
if ($Role -eq 'Master') {
    Write-Host "`n--- Checking Master Network Objects ---" -ForegroundColor Yellow
    $netObjs = & $cliPath networkobjects list 2>&1 | Out-String
    $hasRooms = $netObjs -match 'Location\s+"'
    Record-Result $hasRooms "Master has classroom locations configured" "No classroom locations found in Master directory." $true
    if ($hasRooms) {
        Write-CheckInfo "Current locations/computers summary:`n$($netObjs.Trim())"
    }
}

# Summary
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "                  Verification Summary                   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Role Evaluated : $Role"
Write-Host "  Total Checks   : $TotalChecks"
Write-Host "  Passed         : $PassedChecks" -ForegroundColor Green
Write-Host "  Warnings       : $WarningChecks" -ForegroundColor Yellow
Write-Host "  Failed         : $FailedChecks" -ForegroundColor Red

if ($FailedChecks -eq 0) {
    Write-Host "`n[SUCCESS] All critical verification checks passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[FAILURE] $FailedChecks critical check(s) failed. See output above for remediation." -ForegroundColor Red
    exit 1
}
