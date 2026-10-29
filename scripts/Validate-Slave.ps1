<#
.SYNOPSIS
    Health-check and security audit for Veyon Slave (Student/Client) PC.

.DESCRIPTION
    Validates Slave service status, autostart configuration, public key installation,
    and conducts a strict security audit ensuring no private keys exist on the machine.

.PARAMETER KeyName
    Authentication key identifier (default: 'teacher').

.PARAMETER JsonOutput
    Outputs results strictly as JSON.

.EXAMPLE
    .\Validate-Slave.ps1
    .\Validate-Slave.ps1 -JsonOutput
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
    Write-Host "          Veyon Slave Health & Security Audit             " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
}

# 1. CLI Executable
$cli = Find-VeyonCli
if ($cli) {
    Add-CheckResult "Veyon CLI Executable" "PASS" "Located at $cli"
} else {
    Add-CheckResult "Veyon CLI Executable" "FAIL" "veyon-cli.exe not found" "Install Veyon client on this machine"
}

# 2. Key Security Audit (CRITICAL)
if ($cli) {
    $kOut = & $cli authkeys list 2>&1 | Out-String
    $hasPub = $kOut -match "$KeyName/public"
    $privKeys = @()
    foreach ($l in ($kOut -split "`r?`n")) {
        $t = $l.Trim()
        if ($t -match '/private$') { $privKeys += $t }
    }

    if ($privKeys.Count -gt 0) {
        Add-CheckResult "Private Key Isolation" "FAIL" "SECURITY BREACH: Private key found on Slave ($($privKeys -join ', '))!" "Purge private keys immediately via authkeys delete"
    } else {
        Add-CheckResult "Private Key Isolation" "PASS" "Verified: No private keys exist on this Slave PC"
    }

    if ($hasPub) {
        Add-CheckResult "Public Key Presence" "PASS" "Public key ($KeyName/public) is properly installed"
    } else {
        Add-CheckResult "Public Key Presence" "FAIL" "Public key ($KeyName/public) is missing! Slave cannot authenticate Master." "Import Master public key using Slave installer"
    }
}

# 3. Core Configuration
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
    Add-CheckResult "Authentication Method" "FAIL" "Authentication Method is not Key File (Current: '$mMethod')"
}

$sasVal = Get-CfgVal "Windows/SoftwareSASEnabled"
if ($sasVal -eq "1") {
    Add-CheckResult "Windows Software SAS" "PASS" "Software SAS policy enabled (1)"
} else {
    Add-CheckResult "Windows Software SAS" "WARN" "Software SAS not enabled" "Run setup script as Administrator"
}

# 4. Windows Service
$svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Add-CheckResult "Veyon Windows Service" "PASS" "VeyonService is Running"
    } else {
        Add-CheckResult "Veyon Windows Service" "WARN" "VeyonService is not running (Status: $($svc.Status))" "Start VeyonService"
    }
} else {
    Add-CheckResult "Veyon Windows Service" "FAIL" "VeyonService is not installed on this machine" "Register Veyon service"
}

# 5. Service Autostart
$cim = Get-CimInstance Win32_Service -Filter "Name='VeyonService'" -ErrorAction SilentlyContinue
if ($cim) {
    if ($cim.StartMode -eq 'Auto') {
        Add-CheckResult "Service Startup Mode" "PASS" "Configured for Automatic start on boot"
    } else {
        Add-CheckResult "Service Startup Mode" "WARN" "Service StartMode is $($cim.StartMode) (Expected: Auto)" "Set service startup type to Automatic"
    }
}

# 6. Local Port 11100 Listener
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
    Add-CheckResult "Port 11100 Local Listener" "PASS" "Port 11100 is listening and ready to accept Master connections"
} else {
    Add-CheckResult "Port 11100 Local Listener" "WARN" "Port 11100 is not currently accepting connections"
}

$passCount = @($checks | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq 'WARN' }).Count

$outputObj = [PSCustomObject]@{
    Role = "Slave"
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
        Write-Host "[SUCCESS] Slave validation passed." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[FAILURE] Critical security or service checks failed." -ForegroundColor Red
        exit 1
    }
}
