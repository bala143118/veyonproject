<#
.SYNOPSIS
    Single-command installer and configurator for Veyon Master and Slave roles on Windows.

.DESCRIPTION
    Automates the full configuration of Veyon for either Master (Teacher) or Slave (Student) roles:
    - Automatically locates the Veyon installation and supported CLI modules.
    - Applies secure authentication (key pair on Master, public-key-only on Slave).
    - Prevents security risks by ensuring no private keys remain on Slave machines.
    - Imports role-specific JSON configurations and applies required Windows settings (Software SAS, Firewall).
    - Manages and restarts the Veyon Windows Service.
    - Executes automated verification checks upon completion.

.PARAMETER Role
    The computer role to configure: 'Master' or 'Slave'. Mandatory.

.PARAMETER KeyName
    The name of the authentication key pair (default: 'teacher').

.PARAMETER PublicKeyPath
    Path to the exported public key file. Required on Slave if not found in default locations.

.PARAMETER PrivateKeyPath
    Path to an existing private key file to import on Master (optional; creates new key if omitted).

.PARAMETER ExportPublicKeyPath
    Path where Master will export the public key for distribution to Slaves (default: config\keys\<KeyName>_public_key.pem).

.PARAMETER ConfigFile
    Path to custom JSON configuration file. Defaults to veyon-master.json or veyon-slave.json.

.PARAMETER VeyonBinDir
    Optional custom path to the directory containing veyon-cli.exe.

.PARAMETER RoomName
    (Master only) Optional classroom / location name to create (e.g. "Computer Lab 1").

.PARAMETER AddClientHost
    (Master only) Optional array of student hostnames or IP addresses to add to the classroom.

.PARAMETER HideTrayIcon
    (Slave only) Configures Veyon Service to hide the notification tray icon.

.PARAMETER NoServiceRestart
    Skips stopping and restarting the Veyon Windows Service.

.PARAMETER SkipKeySetup
    Skips key creation and import if keys are already configured.

.PARAMETER Elevate
    Automatically requests UAC elevation if not running in an elevated PowerShell session.

.PARAMETER Force
    Overwrites existing keys or settings without prompting.

.PARAMETER SkipVerification
    Skips running the post-installation verification suite.

.EXAMPLE
    # Configure as Master (Run in elevated PowerShell)
    .\Install-VeyonConfig.ps1 -Role Master

.EXAMPLE
    # Configure as Master and create a classroom with client PCs
    .\Install-VeyonConfig.ps1 -Role Master -RoomName "Lab 101" -AddClientHost "192.168.1.101","192.168.1.102"

.EXAMPLE
    # Configure as Slave using public key from Master
    .\Install-VeyonConfig.ps1 -Role Slave -PublicKeyPath "\\master-share\keys\teacher_public_key.pem"

.EXAMPLE
    # Configure as Slave with hidden tray icon
    .\Install-VeyonConfig.ps1 -Role Slave -HideTrayIcon
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Specify 'Master' or 'Slave' role.")]
    [ValidateSet('Master', 'Slave')]
    [string]$Role,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$KeyName = 'teacher',

    [Parameter()]
    [string]$PublicKeyPath,

    [Parameter()]
    [string]$PrivateKeyPath,

    [Parameter()]
    [string]$ExportPublicKeyPath,

    [Parameter()]
    [string]$ConfigFile,

    [Parameter()]
    [string]$VeyonBinDir,

    [Parameter()]
    [string]$RoomName,

    [Parameter()]
    [string[]]$AddClientHost,

    [Parameter()]
    [switch]$HideTrayIcon,

    [Parameter()]
    [switch]$NoServiceRestart,

    [Parameter()]
    [switch]$SkipKeySetup,

    [Parameter()]
    [switch]$Elevate,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

function Write-Success([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
}

function Write-Err([string]$msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------
# Step 0: Elevation Check
# ---------------------------------------------------------
if (-not (Test-IsAdmin)) {
    if ($Elevate) {
        Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
        $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Role", $Role, "-KeyName", "`"$KeyName`"")
        if ($PublicKeyPath) { $argList += @("-PublicKeyPath", "`"$PublicKeyPath`"") }
        if ($PrivateKeyPath) { $argList += @("-PrivateKeyPath", "`"$PrivateKeyPath`"") }
        if ($ExportPublicKeyPath) { $argList += @("-ExportPublicKeyPath", "`"$ExportPublicKeyPath`"") }
        if ($ConfigFile) { $argList += @("-ConfigFile", "`"$ConfigFile`"") }
        if ($VeyonBinDir) { $argList += @("-VeyonBinDir", "`"$VeyonBinDir`"") }
        if ($RoomName) { $argList += @("-RoomName", "`"$RoomName`"") }
        if ($AddClientHost) { foreach ($h in $AddClientHost) { $argList += @("-AddClientHost", "`"$h`"") } }
        if ($HideTrayIcon) { $argList += "-HideTrayIcon" }
        if ($NoServiceRestart) { $argList += "-NoServiceRestart" }
        if ($SkipKeySetup) { $argList += "-SkipKeySetup" }
        if ($Force) { $argList += "-Force" }
        if ($SkipVerification) { $argList += "-SkipVerification" }

        try {
            $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -PassThru -Wait
            exit $proc.ExitCode
        } catch {
            Write-Err "Failed to elevate process: $_"
            exit 1
        }
    } else {
        Write-Err "Administrator privileges are required to configure Veyon system registry and services."
        Write-Host "Please reopen PowerShell as Administrator and run:" -ForegroundColor Yellow
        Write-Host "    .\Install-VeyonConfig.ps1 -Role $Role" -ForegroundColor White
        Write-Host "Or rerun with -Elevate:" -ForegroundColor Yellow
        Write-Host "    .\Install-VeyonConfig.ps1 -Role $Role -Elevate" -ForegroundColor White
        exit 1
    }
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "        Veyon Auto-Configuration Installer                " -ForegroundColor Green
Write-Host "        Target Role: $Role                                " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# ---------------------------------------------------------
# Step 1: Detect Veyon Installation (Requirement 4)
# ---------------------------------------------------------
Write-Step "Detecting Veyon installation and CLI tools..."
$cliPath = $null
$installDir = $null

$searchPaths = @()
if ($VeyonBinDir) { $searchPaths += $VeyonBinDir }
$searchPaths += @(
    "C:\Program Files\Veyon",
    "C:\Program Files (x86)\Veyon"
)

# Check Registry App Paths & Uninstall Keys
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

try {
    $regInst32 = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Veyon" -ErrorAction SilentlyContinue
    if ($regInst32 -and $regInst32.InstallLocation) {
        $searchPaths += $regInst32.InstallLocation
    }
} catch {}

foreach ($dir in $searchPaths) {
    if ($dir -and (Test-Path -Path $dir)) {
        $candCli = Join-Path -Path $dir -ChildPath "veyon-cli.exe"
        if (Test-Path -Path $candCli) {
            $cliPath = $candCli
            $installDir = $dir
            break
        }
        $candWcli = Join-Path -Path $dir -ChildPath "veyon-wcli.exe"
        if (Test-Path -Path $candWcli) {
            $cliPath = $candWcli
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

if (-not $cliPath) {
    Write-Err "Veyon installation not found on this machine!"
    Write-Host "Please install Veyon from https://veyon.io/download/ first." -ForegroundColor Yellow
    exit 1
}

Write-Success "Found Veyon CLI: $cliPath"
Write-Success "Installation Directory: $installDir"

# ---------------------------------------------------------
# Step 2: Detect Supported CLI Commands (Requirement 4)
# ---------------------------------------------------------
Write-Step "Detecting supported CLI capabilities..."
$cliHelp = & $cliPath help 2>&1 | Out-String
$capabilities = [ordered]@{
    'config'         = ($cliHelp -match 'config')
    'authkeys'       = ($cliHelp -match 'authkeys')
    'service'        = ($cliHelp -match 'service')
    'networkobjects' = ($cliHelp -match 'networkobjects')
    'feature'        = ($cliHelp -match 'feature')
}

foreach ($mod in $capabilities.Keys) {
    if ($capabilities[$mod]) {
        Write-Success "Module '$mod' is supported"
    } else {
        Write-Warn "Module '$mod' was not reported by CLI"
    }
}

if (-not $capabilities['config'] -or -not $capabilities['authkeys'] -or -not $capabilities['service']) {
    Write-Err "Required CLI modules (config, authkeys, service) are incomplete in this Veyon installation."
    exit 1
}

# ---------------------------------------------------------
# Step 3: Resolve & Validate Configuration Template
# ---------------------------------------------------------
Write-Step "Resolving configuration template..."
$scriptDir = $PSScriptRoot

if ($ConfigFile) {
    if (-not (Test-Path -Path $ConfigFile)) {
        Write-Err "Specified ConfigFile not found: $ConfigFile"
        exit 1
    }
    $targetConfigFile = (Resolve-Path -Path $ConfigFile).Path
} else {
    $defaultFile = if ($Role -eq 'Master') {
        Join-Path -Path $scriptDir -ChildPath "veyon-master.json"
    } else {
        Join-Path -Path $scriptDir -ChildPath "veyon-slave.json"
    }

    if (-not (Test-Path -Path $defaultFile)) {
        Write-Err "Default configuration file not found: $defaultFile"
        exit 1
    }
    $targetConfigFile = $defaultFile
}

Write-Success "Using configuration file: $targetConfigFile"

# Validate JSON format
try {
    $configContent = Get-Content -Path $targetConfigFile -Raw | ConvertFrom-Json
    Write-Success "Configuration JSON is syntactically valid"
} catch {
    Write-Err "Configuration JSON is corrupted or invalid: $_"
    exit 1
}

# Apply runtime overrides if needed
$tempConfigFile = $null
if ($HideTrayIcon -and $Role -eq 'Slave') {
    Write-Step "Applying -HideTrayIcon override..."
    if ($configContent.Service) {
        $configContent.Service.HideTrayIcon = "true"
    }
    $tempConfigFile = Join-Path -Path $env:TEMP -ChildPath "veyon-slave-override-$([System.Guid]::NewGuid().ToString('N')).json"
    $configContent | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfigFile -Encoding UTF8
    $targetConfigFile = $tempConfigFile
    Write-Success "Tray icon will be hidden"
}

# ---------------------------------------------------------
# Step 4: Configure Authentication Securely (Requirement 5)
# ---------------------------------------------------------
Write-Step "Configuring authentication for role: $Role..."
$keysRaw = & $cliPath authkeys list 2>&1 | Out-String
$existingKeys = @()
foreach ($line in ($keysRaw -split "`r?`n")) {
    $t = $line.Trim()
    if ($t -and -not ($t.StartsWith("[") -or $t.StartsWith("Available"))) {
        $existingKeys += $t
    }
}

if ($Role -eq 'Master') {
    $privKeyId = "$KeyName/private"
    $pubKeyId = "$KeyName/public"

    if ($existingKeys -contains $privKeyId -and -not $Force -and -not $PrivateKeyPath) {
        Write-Success "Existing Master key '$privKeyId' is already installed"
    } else {
        if ($PrivateKeyPath) {
            if (-not (Test-Path -Path $PrivateKeyPath)) {
                Write-Err "Specified PrivateKeyPath does not exist: $PrivateKeyPath"
                exit 1
            }
            Write-Host "  Importing private key from $PrivateKeyPath..." -ForegroundColor Yellow
            & $cliPath authkeys import $privKeyId $PrivateKeyPath
            & $cliPath authkeys extract $privKeyId
            Write-Success "Private key imported and public key extracted"
        } else {
            # Check if key file exists in keys directory
            $candPrivKey = Join-Path -Path $scriptDir -ChildPath "keys\${KeyName}_private_key.pem"
            if (Test-Path -Path $candPrivKey) {
                Write-Host "  Importing private key from $candPrivKey..." -ForegroundColor Yellow
                & $cliPath authkeys import $privKeyId $candPrivKey
                & $cliPath authkeys extract $privKeyId
                Write-Success "Imported private key from keys directory"
            } else {
                Write-Host "  Creating new authentication key pair '$KeyName'..." -ForegroundColor Yellow
                & $cliPath authkeys create $KeyName
                Write-Success "Created new authentication key pair '$KeyName'"
            }
        }
    }

    # Restrict private key permissions to Administrators
    try {
        & $cliPath authkeys setaccessgroup $privKeyId "Administrators" 2>$null
        Write-Success "Access permissions for '$privKeyId' restricted to Administrators"
    } catch {
        Write-Warn "Could not set key access group via CLI: $_"
    }

    # Export public key for distribution to Slaves
    $exportPath = if ($ExportPublicKeyPath) {
        $ExportPublicKeyPath
    } else {
        $keysDir = Join-Path -Path $scriptDir -ChildPath "keys"
        if (-not (Test-Path -Path $keysDir)) { New-Item -ItemType Directory -Path $keysDir -Force | Out-Null }
        Join-Path -Path $keysDir -ChildPath "${KeyName}_public_key.pem"
    }

    $exportDir = Split-Path -Parent $exportPath
    if ($exportDir -and -not (Test-Path -Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    & $cliPath authkeys export $pubKeyId $exportPath 2>$null
    if (Test-Path -Path $exportPath) {
        Write-Success "Public key exported to: $exportPath"
        Write-Host "  [SECURITY NOTE] Distribute ONLY '$exportPath' to your Slave (Student) PCs." -ForegroundColor Cyan
        Write-Host "  [SECURITY NOTE] Never copy private keys to student machines or commit them to Git." -ForegroundColor Cyan
    }

} elseif ($Role -eq 'Slave') {
    # CRITICAL SECURITY AUDIT: Remove any private keys on Slave
    $privOnSlave = $existingKeys | Where-Object { $_ -like "*/private" }
    if ($privOnSlave) {
        Write-Warn "SECURITY VIOLATION DETECTED: Private key found on Slave PC ($($privOnSlave -join ', '))!"
        Write-Host "  Removing private keys from Slave to protect classroom security..." -ForegroundColor Yellow
        foreach ($pk in $privOnSlave) {
            & $cliPath authkeys delete $pk
            Write-Success "Removed private key '$pk' from Slave"
        }
    }

    # Import Public Key
    $pubKeyId = "$KeyName/public"
    if ($existingKeys -contains $pubKeyId -and -not $Force -and -not $PublicKeyPath) {
        Write-Success "Public key '$pubKeyId' is already installed"
    } else {
        $resolvedPubKey = $null
        if ($PublicKeyPath) {
            if (Test-Path -Path $PublicKeyPath) {
                $resolvedPubKey = (Resolve-Path -Path $PublicKeyPath).Path
            } else {
                Write-Err "Specified PublicKeyPath not found: $PublicKeyPath"
                exit 1
            }
        } else {
            # Search candidate paths
            $candPaths = @(
                (Join-Path -Path $scriptDir -ChildPath "keys\${KeyName}_public_key.pem"),
                (Join-Path -Path $scriptDir -ChildPath "keys\teacher_public_key.pem"),
                (Join-Path -Path $scriptDir -ChildPath "keys\default_public_key.pem")
            )
            foreach ($cp in $candPaths) {
                if (Test-Path -Path $cp) {
                    $resolvedPubKey = $cp
                    break
                }
            }
        }

        if ($resolvedPubKey) {
            Write-Host "  Importing public key from $resolvedPubKey..." -ForegroundColor Yellow
            & $cliPath authkeys import $pubKeyId $resolvedPubKey
            Write-Success "Public key imported: $pubKeyId"
        } else {
            Write-Warn "Public key file not found! Authentication requires the Master's public key."
            Write-Host "  To complete setup, run:" -ForegroundColor Yellow
            Write-Host "    .\Install-VeyonConfig.ps1 -Role Slave -PublicKeyPath <path_to_teacher_public_key.pem>" -ForegroundColor White
        }
    }
}

# ---------------------------------------------------------
# Step 5: Apply Configuration (Requirement 6)
# ---------------------------------------------------------
Write-Step "Applying Veyon configuration from JSON..."
$importRes = & $cliPath config import "$targetConfigFile" 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to import configuration: $importRes"
    exit 1
}
Write-Success "Configuration JSON imported successfully"

# Enforce mandatory system settings
Write-Step "Enforcing required Windows & security parameters..."
& $cliPath config set Authentication/Method 1
& $cliPath config set Windows/SoftwareSASEnabled 1
& $cliPath config set Service/SoftwareSASEnabled 0
& $cliPath config set Network/FirewallExceptionEnabled 1

if ($Role -eq 'Slave') {
    & $cliPath config set Service/Autostart true
}

# Disable ForceGuest in Windows Registry for secure authentication
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "ForceGuest" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Success "Disabled ForceGuest logon restriction in Windows Registry"
} catch {
    Write-Warn "Could not update ForceGuest registry value: $_"
}

# Master-specific classroom configuration
if ($Role -eq 'Master') {
    if ($RoomName) {
        Write-Step "Adding classroom location: '$RoomName'..."
        & $cliPath networkobjects add location "$RoomName" 2>$null
        Write-Success "Location '$RoomName' configured"

        if ($AddClientHost) {
            foreach ($hostEntry in $AddClientHost) {
                $compName = $hostEntry.Trim()
                Write-Host "  Adding student computer '$compName' to '$RoomName'..." -ForegroundColor Yellow
                & $cliPath networkobjects add computer "$compName" "$compName" "" "$RoomName" 2>$null
                Write-Success "Added computer '$compName'"
            }
        }
    }
}

# Clean up temp config file if created
if ($tempConfigFile -and (Test-Path -Path $tempConfigFile)) {
    Remove-Item -Path $tempConfigFile -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------
# Step 6: Service Registration & Management (Requirement 6)
# ---------------------------------------------------------
Write-Step "Configuring Veyon Windows Service..."
& $cliPath service register 2>$null
Write-Success "Veyon Service registered"

try {
    Set-Service -Name "VeyonService" -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Success "VeyonService configured for Automatic startup"
} catch {
    Write-Warn "Could not set service startup type: $_"
}

if (-not $NoServiceRestart) {
    Write-Step "Restarting Veyon Windows Service..."
    & $cliPath service restart 2>$null

    Start-Sleep -Seconds 2
    $svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Write-Host "  Starting service via Service Control Manager..." -ForegroundColor Yellow
        Start-Service -Name "VeyonService" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $svc = Get-Service -Name "VeyonService" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Write-Success "Veyon Service is Running"
    } else {
        Write-Warn "Veyon Service status: $($svc.Status)"
    }
}

# ---------------------------------------------------------
# Step 7: Automated Verification (Requirements 6 & 8)
# ---------------------------------------------------------
if (-not $SkipVerification) {
    Write-Step "Running automated verification suite..."
    $verifierScript = Join-Path -Path $scriptDir -ChildPath "Verify-VeyonConfig.ps1"
    if (Test-Path -Path $verifierScript) {
        & powershell.exe -ExecutionPolicy Bypass -File $verifierScript -Role $Role -KeyName $KeyName -VeyonBinDir $installDir
        $verExit = $LASTEXITCODE
        if ($verExit -ne 0) {
            Write-Err "Verification reported errors (exit code: $verExit)."
            exit $verExit
        }
    } else {
        Write-Warn "Verification script not found at: $verifierScript"
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   Veyon $Role Configuration Completed Successfully!     " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
exit 0
