<#
.SYNOPSIS
    Starts the Veyon Web Administration Dashboard.

.DESCRIPTION
    Launches the local Flask backend server for the Veyon Master/Slave management dashboard.
    Recommended to run from an elevated Windows PowerShell console ("Run as Administrator")
    so configuration and service management actions can be applied without elevation prompts.

.PARAMETER Port
    Port number to listen on (default: 5000).

.PARAMETER NoBrowser
    Do not automatically launch the web browser.

.EXAMPLE
    .\run_dashboard.ps1
    .\run_dashboard.ps1 -Port 8080 -NoBrowser
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$Port = 5000,

    [Parameter()]
    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     Veyon Web Administration Dashboard Launcher         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Python
$pythonCmd = Get-Command "python.exe" -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Host "[ERROR] Python 3 was not found in PATH." -ForegroundColor Red
    Write-Host "Please install Python 3.9+ from https://www.python.org/ or the Microsoft Store." -ForegroundColor Yellow
    exit 1
}

# 2. Check Flask
$hasFlask = $false
try {
    & python.exe -c "import flask" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hasFlask = $true
    }
} catch {}

if (-not $hasFlask) {
    Write-Host "[INFO] Installing required dependencies (Flask)..." -ForegroundColor Yellow
    & python.exe -m pip install -r (Join-Path -Path $PSScriptRoot -ChildPath "requirements.txt")
}

# 3. Check Administrator Status
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "[OK] Running with Administrator privileges (Full Service & System Config Control)." -ForegroundColor Green
} else {
    Write-Host "[NOTE] Running as Standard User." -ForegroundColor Yellow
    Write-Host "      Some operations (service restart, firewall changes) will require elevation." -ForegroundColor DarkGray
    Write-Host "      To run with full privileges, reopen PowerShell as Administrator." -ForegroundColor DarkGray
}

$url = "http://127.0.0.1:$Port"
Write-Host "`n[STARTING] Dashboard server listening at: $url" -ForegroundColor Cyan
Write-Host "[HINT] Press Ctrl+C in this console to stop the dashboard server.`n" -ForegroundColor DarkGray

if (-not $NoBrowser) {
    Start-Process $url
}

$env:PORT = $Port.ToString()
$appScript = Join-Path -Path $PSScriptRoot -ChildPath "app.py"
& python.exe "$appScript"
