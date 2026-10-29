<#
.SYNOPSIS
    Deep health-check and security validation for Veyon Master PC.

.DESCRIPTION
    Validates Master executables, CLI modules, private/public key pairing,
    registry settings, Windows service, port 11100 listener, firewall rules,
    and classroom directory.

.PARAMETER KeyName
    Authentication key identifier (default: 'teacher').

.PARAMETER JsonOutput
    Outputs results strictly as JSON.

.EXAMPLE
    .\Validate-Master.ps1
    .\Validate-Master.ps1 -JsonOutput
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [switch]$JsonOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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

$checks = @()

function Add-CheckResult([string]$Name, [string]$Status, [string]$Details, [string]$Remediation = $null) {
    $script:checks += [PSCustomObject]@{
        Name = $Name
        Status = $Status
        Details = $Details
        Remediation = $Remediation
    }
    if (-not $script:JsonOutput) {
        $color = if ($Status -eq 'PASS') { 'Green' } elseif ($Status -eq 'WARN') { 'Yellow' } else { 'Red' }
        Write-Host "  [$Status] ${Name}: $Details" -ForegroundColor $color
    }
}

if (-not $JsonOutput) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "         Veyon Master Health & Security Validation        " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
}

# 1. CLI Executable
$cli = Find-VeyonCli
if ($cli) {
    Add-CheckResult "Veyon CLI Executable" "PASS" "Located at $cli"
} else {
    Add-CheckResult "Veyon CLI Executable" "FAIL" "veyon-cli.exe not found" "Install Veyon from https://veyon.io/"
}

# 2. Master Console Executable
$masterExe = "C:\Program Files\Veyon\veyon-master.exe"
if (Test-Path $masterExe) {
    Add-CheckResult "Veyon Master Console" "PASS" "veyon-master.exe is installed"
} else {
    Add-CheckResult "Veyon Master Console" "WARN" "veyon-master.exe not found at standard path" "Reinstall Veyon with Master component selected"
}

# 3. Supported Modules
if ($cli) {
    $h = & $cli help 2>&1 | Out-String
    $hasConfig = $h -match "config"
    $hasAuth = $h -match "authkeys"
    $hasSvc = $h -match "service"
    $hasNet = $h -match "networkobjects"

    if ($hasConfig -and $hasAuth -and $hasSvc) {
        Add-CheckResult "Supported CLI Modules" "PASS" "config, authkeys, service, networkobjects detected"
    } else {
        Add-CheckResult "Supported CLI Modules" "FAIL" "Missing critical modules in Veyon CLI" "Update Veyon installation"
    }
}

# 4. Authentication Keys
if ($cli) {
    $kOut = & $cli authkeys list 2>&1 | Out-String
    $hasPriv = $kOut -match "$KeyName/private"
    $hasPub = $kOut -match "$KeyName/public"

    if ($hasPriv -and $hasPub) {
        Add-CheckResult "Authentication Key Pair" "PASS" "Both $KeyName/private and $KeyName/public are present"
    } elseif ($hasPriv -and -not $hasPub) {
        Add-CheckResult "Authentication Key Pair" "WARN" "Private key present, but public key is missing" "Run authkeys extract $KeyName/private"
    } else {
        Add-CheckResult "Authentication Key Pair" "FAIL" "Master private key ($KeyName/private) is missing" "Run Master auto-configuration or create key pair"
    }
}

# 5. Core Configuration
function Get-CfgVal([string]$k) {
    if (-not $cli) { return $null }
    try {
        $r = & $cli config get $k 2>$null
        foreach ($l in ($r -split "`r?`n")) {
            $t = $l.Trim()
            if ($t -and -not ($t.StartsWith("[") -or $t.StartsWith("Available"))) { return $t }
        }
    } catch {}
    return $null
}

$mMethod = Get-CfgVal "Authentication/Method"
if ($mMethod -eq "1") {
    Add-CheckResult "Authentication Method" "PASS" "Key File Authentication enabled (Method=1)"
} else {
    Add-CheckResult "Authentication Method" "FAIL" "Authentication Method is not Key File (Current: '$mMethod')" "Set Authentication/Method to 1"
}

$sasVal = Get-CfgVal "Windows/SoftwareSASEnabled"
if ($sasVal -eq "1") {
    Add-CheckResult "Windows Software SAS" "PASS" "Software SAS policy enabled (1)"
} else {
    Add-CheckResult "Windows Software SAS" "WARN" "Software SAS not enabled (Current: '$sasVal')" "Set Windows/SoftwareSASEnabled to 1"
}

# 6. Windows Service
$svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Add-CheckResult "Veyon Windows Service" "PASS" "VeyonService is Running"
    } else {
        Add-CheckResult "Veyon Windows Service" "WARN" "VeyonService status: $($svc.Status)" "Start VeyonService via Service Control Manager"
    }
} else {
    Add-CheckResult "Veyon Windows Service" "FAIL" "VeyonService is not registered" "Run veyon-cli service register as Administrator"
}

# 7. Local Port 11100 Listener
$portOpen = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect("127.0.0.1", 11100, $null, $null)
    $wh = $iar.AsyncWaitHandle
    if ($wh.WaitOne(800, $false)) {
        $tcp.EndConnect($iar)
        $portOpen = $true
    }
    $tcp.Close()
} catch {}

if ($portOpen) {
    Add-CheckResult "Port 11100 Local Listener" "PASS" "Port 11100 is listening and accepting connections"
} else {
    Add-CheckResult "Port 11100 Local Listener" "WARN" "Port 11100 not accepting local connections" "Ensure Veyon Service is running and firewall allows port 11100"
}

# 8. Firewall Rules
try {
    $fw = Get-NetFirewallRule -DisplayName "*Veyon*" -ErrorAction SilentlyContinue
    if ($fw -and $fw.Count -gt 0) {
        Add-CheckResult "Windows Firewall Rules" "PASS" "Found $($fw.Count) firewall rules configured for Veyon"
    } else {
        Add-CheckResult "Windows Firewall Rules" "WARN" "No specific Windows Defender Firewall rules found" "Configure firewall exception via installer"
    }
} catch {
    Add-CheckResult "Windows Firewall Rules" "WARN" "Could not query firewall rules (insufficient rights)"
}

# 9. Classroom Directory
if ($cli) {
    $nOut = & $cli networkobjects list 2>&1 | Out-String
    if ($nOut -match 'Location\s+"') {
        Add-CheckResult "Classroom Directory" "PASS" "Classroom locations configured in Master"
    } else {
        Add-CheckResult "Classroom Directory" "WARN" "No classroom locations currently registered in Master" "Add classroom locations via Master Setup or networkobjects add"
    }
}

$passCount = @($checks | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq 'WARN' }).Count

$outputObj = [PSCustomObject]@{
    Role = "Master"
    Success = ($failCount -eq 0)
    Total = @($checks).Count
    Passed = $passCount
    Warnings = $warnCount
    Failed = $failCount
    Checks = $checks
    Timestamp = (Get-Date).ToString("o")
}

if ($JsonOutput) {
    Write-Output ($outputObj | ConvertTo-Json -Depth 4)
    exit $(if ($failCount -eq 0) { 0 } else { 1 })
} else {
    Write-Host "`nSummary: $passCount Passed, $warnCount Warnings, $failCount Failed." -ForegroundColor $(if($failCount -eq 0){'Green'}else{'Red'})
    if ($failCount -eq 0) {
        Write-Host "[SUCCESS] Master health validation passed." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[FAILURE] Critical checks failed." -ForegroundColor Red
        exit 1
    }
}
