# Veyon Master/Slave Automated Configuration Guide for Windows

This guide provides step-by-step instructions for deploying and configuring **Veyon Master (Teacher)** and **Veyon Slave (Student/Client)** systems on Windows using the automated PowerShell installer scripts and role-specific configurations.

---

## 1. Overview & Architecture

Veyon consists of two primary operational roles:

| Component | Role | Required Keys | Primary Applications & Services |
| :--- | :--- | :--- | :--- |
| **Master** | Teacher / Admin PC | **Private Key** + **Public Key** | `veyon-master.exe` (Management Console), `veyon-service.exe` |
| **Slave** | Student / Client PC | **Public Key ONLY** *(Private keys must never exist on Slaves)* | `veyon-service.exe` (Background Service), `veyon-server.exe` |

### Security Model (Key File Authentication)
- Authentication uses 4096-bit RSA asymmetric key pairs.
- The **Master** holds the private key (`teacher/private`), which signs connection tokens.
- The **Slave** holds only the public key (`teacher/public`), used to verify connections from the Master.
- **Critical Security Rule**: Private keys must **never** be placed on student computers, and must **never** be committed to version control. The repository includes `.gitignore` rules in `config/` to safeguard private keys.

---

## 2. Prerequisites

1. **Install Veyon on all machines**:
   - Download the official Veyon installer for Windows from [https://veyon.io/download/](https://veyon.io/download/).
   - Run the installer with default options (installs to `C:\Program Files\Veyon`).
   - On Slave-only PCs, you may optionally install without the Master component.
2. **Administrator Rights**:
   - PowerShell commands that apply system configurations and restart Windows services must be run from an **Elevated PowerShell** prompt (`Run as Administrator`).

---

## 3. Quick Start: Single-Command Installation

Open **Windows PowerShell as Administrator** and navigate to the project directory:

```powershell
cd E:\veyon
```

### Option A: Setup Master (Teacher PC)

Run the single-command installer with `-Role Master`:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Install-VeyonConfig.ps1 -Role Master
```

Or from within the `config` directory:
```powershell
cd config
.\Install-VeyonConfig.ps1 -Role Master
```

#### What this does automatically:
1. Detects `C:\Program Files\Veyon\veyon-cli.exe` and verifies supported CLI modules.
2. Generates an asymmetric RSA key pair (`teacher`) if one does not already exist.
3. Sets NTFS access permissions on the private key to `Administrators` only.
4. Exports the public key to `config\keys\teacher_public_key.pem`.
5. Imports the optimized Master configuration from `veyon-master.json`.
6. Enforces Windows Software SAS (`Windows/SoftwareSASEnabled = 1`) for Ctrl+Alt+Del remote control.
7. Disables Windows `ForceGuest` restriction.
8. Registers and restarts `VeyonService` with Automatic startup.
9. Runs automated verification and reports health checks.

#### Optional: Create Classrooms and Add Student PCs Directly
```powershell
.\config\Install-VeyonConfig.ps1 -Role Master `
    -RoomName "Computer Lab 1" `
    -AddClientHost "192.168.1.101", "192.168.1.102", "192.168.1.103"
```

---

### Step 4: Transfer Public Key to Slave PCs

After configuring the Master, distribute the exported **public key** (`config\keys\teacher_public_key.pem`) to each Slave PC or place it on a network share accessible by the Slaves:

- Source path on Master: `config\keys\teacher_public_key.pem`
- **DO NOT copy the private key!**

---

### Option B: Setup Slave (Student PC)

On each student PC, open **Windows PowerShell as Administrator** and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Install-VeyonConfig.ps1 -Role Slave -PublicKeyPath "C:\path\to\teacher_public_key.pem"
```

If the public key was already copied into the local `config\keys\` folder, you can run simply:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Install-VeyonConfig.ps1 -Role Slave
```

#### What this does automatically:
1. Detects Veyon CLI and supported commands.
2. **Security Audit**: Scans for and removes any private keys found on the Slave PC.
3. Imports the Master's public key (`teacher/public`).
4. Imports the Slave configuration from `veyon-slave.json`.
5. Enables Windows Software SAS policy.
6. Configures Windows Firewall exception for Veyon Server (ports 11100-11400).
7. Sets `VeyonService` startup to Automatic and restarts the service.
8. Runs automated verification.

#### Optional: Hide Notification Area Tray Icon on Slaves
To prevent students from seeing or interacting with the Veyon tray icon:
```powershell
.\config\Install-VeyonConfig.ps1 -Role Slave -HideTrayIcon
```

---

## 4. Verification & Health Check

At any time, you can verify your configuration without modifying settings using `Verify-VeyonConfig.ps1`:

### Verify Master Configuration:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Verify-VeyonConfig.ps1 -Role Master
```

### Verify Slave Configuration:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Verify-VeyonConfig.ps1 -Role Slave
```

### Auto-Detect Role and Verify:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\config\Verify-VeyonConfig.ps1 -Role Auto
```

### Expected Output:
```text
==========================================================
       Veyon Configuration & Security Verifier           
==========================================================
  [PASS] Veyon CLI detected at: C:\Program Files\Veyon\veyon-cli.exe
  [PASS] CLI module 'config' is supported
  [PASS] CLI module 'authkeys' is supported
  [PASS] CLI module 'service' is supported
  [INFO] Installed authentication keys: teacher/private, teacher/public

--- Checking Authentication Security (Role: Master) ---
  [PASS] Master private key (teacher/private) is present
  [PASS] Master public key (teacher/public) is present

--- Checking Configuration Parameters ---
  [PASS] Authentication Method is Key File Authentication (Method = 1)
  [PASS] Windows Software SAS is enabled (SoftwareSASEnabled = 1)
  [PASS] Firewall exceptions setting is enabled (FirewallExceptionEnabled = 1)
  [PASS] Veyon Server port is standard (11100)

--- Checking Veyon Windows Service ---
  [PASS] VeyonService is installed in Windows Service Control Manager
  [PASS] VeyonService is Running
  [PASS] VeyonService StartMode is Automatic

--- Checking Windows Firewall Exceptions ---
  [PASS] Windows Defender Firewall rules for Veyon found (2 rules)

--- Checking Master Network Objects ---
  [PASS] Master has classroom locations configured

==========================================================
                  Verification Summary                   
==========================================================
  Role Evaluated : Master
  Total Checks   : 15
  Passed         : 15
  Warnings       : 0
  Failed         : 0

[SUCCESS] All critical verification checks passed!
```

---

## 5. Script Parameters Reference

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-Role` | String | *(Mandatory)* | `'Master'` or `'Slave'`. |
| `-KeyName` | String | `'teacher'` | Authentication key pair identifier name. |
| `-PublicKeyPath` | String | Auto-detected | Path to public key file for import. |
| `-PrivateKeyPath` | String | Auto-generated | Path to private key file to import (Master only). |
| `-ExportPublicKeyPath`| String | `config\keys\<KeyName>_public_key.pem` | Path where Master exports the public key. |
| `-ConfigFile` | String | `veyon-master.json` / `veyon-slave.json` | Custom JSON configuration file. |
| `-VeyonBinDir` | String | Auto-detected | Custom path to folder containing `veyon-cli.exe`. |
| `-RoomName` | String | None | (Master only) Classroom/Room name to register. |
| `-AddClientHost` | String[] | None | (Master only) Array of student hostnames or IP addresses. |
| `-HideTrayIcon` | Switch | `false` | (Slave only) Hide notification icon on student desktop. |
| `-NoServiceRestart` | Switch | `false` | Skip restarting the `VeyonService`. |
| `-SkipKeySetup` | Switch | `false` | Skip key creation/import if keys exist. |
| `-Elevate` | Switch | `false` | Re-launch script with administrative elevation prompt. |
| `-Force` | Switch | `false` | Overwrite existing keys and settings without prompting. |
| `-SkipVerification` | Switch | `false` | Skip post-installation verification check. |

---

## 6. Network & Firewall Configuration

Ensure the following TCP ports are allowed on your local network/subnets between Master and Slave:

| Port | Protocol | Purpose |
| :--- | :--- | :--- |
| `11100` | TCP | Veyon Server control channel |
| `11200` | TCP | VNC screen transfer |
| `11300` | TCP | Feature Worker Manager |
| `11400` | TCP | Demo Server (screen broadcast to students) |

The installer automatically enables `Network/FirewallExceptionEnabled = 1` and registers Windows Defender Firewall rules for `Veyon Server` and `Veyon Worker`.

---

## 7. Troubleshooting

### "Configuration is not writable. Please check your permissions!"
- **Cause**: Script or CLI command was run without administrative rights.
- **Solution**: Open PowerShell using **Run as Administrator**, or run with `-Elevate`:
  ```powershell
  .\config\Install-VeyonConfig.ps1 -Role Master -Elevate
  ```

### "Private key found on Slave" Security Warning
- **Cause**: A private key was inadvertently copied to a student PC.
- **Solution**: The installer automatically purges private keys on Slaves. Alternatively, run:
  ```powershell
  & "C:\Program Files\Veyon\veyon-cli.exe" authkeys delete teacher/private
  ```

### Client PC shows "Unreachable" in Veyon Master
1. Verify the client IP / hostname in Master matches the student PC.
2. Confirm `VeyonService` is running on the client: `Get-Service VeyonService`.
3. Test network connectivity from Master:
   ```powershell
   Test-NetConnection -ComputerName <Client-IP> -Port 11100
   ```
4. Verify the public key on the client matches the Master:
   ```powershell
   & "C:\Program Files\Veyon\veyon-cli.exe" authkeys list
   ```
