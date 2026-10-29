#!/usr/bin/env python3
"""
Comprehensive 10-Point Diagnostic Engine
Performs actual system inspections with actionable remediation advice.
"""

import os
import platform
import subprocess
from typing import Dict, Any, List

from modules.system_info import is_admin, check_port_listening, get_service_status
from modules.veyon_cli import find_veyon_cli, get_auth_keys, get_config_value, get_supported_modules

def run_diagnostics() -> Dict[str, Any]:
    checks = []

    # Check 1: Operating System & Architecture
    os_name = platform.platform()
    checks.append({
        "id": 1,
        "name": "Operating System & Architecture",
        "status": "PASS",
        "details": f"Running {os_name} (Architecture: {platform.machine()})",
        "remediation": None
    })

    # Check 2: Administrator / Elevation Rights
    elevated = is_admin()
    checks.append({
        "id": 2,
        "name": "Administrator / Elevation Rights",
        "status": "PASS" if elevated else "WARN",
        "details": "Process has full Administrator privileges" if elevated else "Running with Standard User token (Limited UAC)",
        "remediation": "Re-launch PowerShell/backend as Administrator to modify services, HKLM, and firewall rules without prompts" if not elevated else None
    })

    # Check 3: Veyon Installation & Core Executables
    cli_path = find_veyon_cli()
    master_exe = r"C:\Program Files\Veyon\veyon-master.exe"
    service_exe = r"C:\Program Files\Veyon\veyon-service.exe"

    has_cli = cli_path and os.path.exists(cli_path)
    has_master = os.path.exists(master_exe)
    has_svc_exe = os.path.exists(service_exe)

    if has_cli and has_master and has_svc_exe:
        checks.append({
            "id": 3,
            "name": "Veyon Installation & Binaries",
            "status": "PASS",
            "details": f"Found CLI ({cli_path}), Master Console, and Service binary",
            "remediation": None
        })
    elif has_cli:
        checks.append({
            "id": 3,
            "name": "Veyon Installation & Binaries",
            "status": "WARN",
            "details": f"CLI detected at {cli_path}, but some binaries (Master/Service) may be custom or absent",
            "remediation": "Ensure standard Veyon installation at C:\\Program Files\\Veyon"
        })
    else:
        checks.append({
            "id": 3,
            "name": "Veyon Installation & Binaries",
            "status": "FAIL",
            "details": "Veyon is not installed on this machine or veyon-cli.exe is missing",
            "remediation": "Download and install Veyon from https://veyon.io/download/"
        })

    # Check 4: Supported CLI Modules
    modules = get_supported_modules(cli_path)
    req_modules = ["config", "authkeys", "service", "networkobjects"]
    missing = [m for m in req_modules if m not in modules]
    if not missing:
        checks.append({
            "id": 4,
            "name": "Supported CLI Commands",
            "status": "PASS",
            "details": f"All critical modules present: {', '.join(modules)}",
            "remediation": None
        })
    else:
        checks.append({
            "id": 4,
            "name": "Supported CLI Commands",
            "status": "FAIL",
            "details": f"Missing critical CLI modules: {', '.join(missing)}",
            "remediation": "Reinstall or upgrade Veyon to version 4.8+"
        })

    # Check 5: Veyon Windows Service
    svc = get_service_status()
    if svc["status"] == "Running":
        checks.append({
            "id": 5,
            "name": "Veyon Windows Service (VeyonService)",
            "status": "PASS",
            "details": f"Service is active and Running (Startup: {svc.get('start_type', 'Auto')})",
            "remediation": None
        })
    elif svc["installed"]:
        checks.append({
            "id": 5,
            "name": "Veyon Windows Service (VeyonService)",
            "status": "WARN",
            "details": f"Service is installed but status is: {svc['status']}",
            "remediation": "Start VeyonService via Service Control Manager or the dashboard Quick Action"
        })
    else:
        checks.append({
            "id": 5,
            "name": "Veyon Windows Service (VeyonService)",
            "status": "FAIL",
            "details": "VeyonService is not registered in Windows Service Control Manager",
            "remediation": "Run veyon-cli service register in an elevated console"
        })

    # Check 6: Port 11100 Local Listener (Socket)
    port_open = check_port_listening(11100)
    checks.append({
        "id": 6,
        "name": "Veyon Server Port 11100 (Local Socket)",
        "status": "PASS" if port_open else "WARN",
        "details": "Port 11100 is actively listening and accepting connections" if port_open else "Port 11100 is not currently accepting connections",
        "remediation": "Verify Veyon Service is running and configured with standard port 11100" if not port_open else None
    })

    # Check 7: Windows Defender Firewall Exceptions
    fw_count = 0
    try:
        res = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", "(Get-NetFirewallRule -DisplayName '*Veyon*').Count"],
            stdout=subprocess.PIPE, text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        if res.returncode == 0 and res.stdout.strip().isdigit():
            fw_count = int(res.stdout.strip())
    except Exception:
        pass

    if fw_count > 0:
        checks.append({
            "id": 7,
            "name": "Windows Defender Firewall Rules",
            "status": "PASS",
            "details": f"Found {fw_count} inbound firewall rules configured for Veyon Server/Worker",
            "remediation": None
        })
    else:
        checks.append({
            "id": 7,
            "name": "Windows Defender Firewall Rules",
            "status": "WARN",
            "details": "No dedicated Veyon firewall rules found in Windows Defender Firewall",
            "remediation": "Run Master or Slave setup as Administrator to configure firewall exceptions"
        })

    # Check 8: Authentication Key Pair Security
    keys = get_auth_keys(cli_path)
    has_priv = any("private" in k for k in keys)
    has_pub = any("public" in k for k in keys)

    if has_priv and has_pub:
        checks.append({
            "id": 8,
            "name": "Authentication Key Pair",
            "status": "PASS",
            "details": f"Master key pair installed: {', '.join(keys)}",
            "remediation": None
        })
    elif has_pub and not has_priv:
        checks.append({
            "id": 8,
            "name": "Authentication Key Pair",
            "status": "PASS",
            "details": f"Slave public key installed: {', '.join(keys)} (No private keys exposed)",
            "remediation": None
        })
    else:
        checks.append({
            "id": 8,
            "name": "Authentication Key Pair",
            "status": "WARN",
            "details": f"Keys detected: {', '.join(keys) if keys else 'None'}",
            "remediation": "Generate or import key pair using the Master Configuration page"
        })

    # Check 9: Windows Software SAS (Ctrl+Alt+Del Policy)
    sas = get_config_value("Windows/SoftwareSASEnabled", cli_path)
    if sas == "1":
        checks.append({
            "id": 9,
            "name": "Windows Software SAS (Ctrl+Alt+Del Policy)",
            "status": "PASS",
            "details": "Software SAS policy is enabled (SoftwareSASEnabled = 1)",
            "remediation": None
        })
    else:
        checks.append({
            "id": 9,
            "name": "Windows Software SAS (Ctrl+Alt+Del Policy)",
            "status": "WARN",
            "details": f"Software SAS not enabled (Current: '{sas or '0'}')",
            "remediation": "Run Master/Slave setup as Administrator to apply Software SAS policy"
        })

    # Check 10: Backend API & Database Health
    from database import DB_PATH
    db_ok = DB_PATH.exists() and os.path.getsize(str(DB_PATH)) > 0
    checks.append({
        "id": 10,
        "name": "Backend Engine & SQLite Database",
        "status": "PASS" if db_ok else "FAIL",
        "details": f"Persistent SQLite database active at: {DB_PATH.name} ({os.path.getsize(str(DB_PATH)) if db_ok else 0} bytes)",
        "remediation": "Restart dashboard backend to reinitialize database" if not db_ok else None
    })

    pass_count = sum(1 for c in checks if c["status"] == "PASS")
    warn_count = sum(1 for c in checks if c["status"] == "WARN")
    fail_count = sum(1 for c in checks if c["status"] == "FAIL")

    return {
        "success": True,
        "total": len(checks),
        "passed": pass_count,
        "warnings": warn_count,
        "failed": fail_count,
        "checks": checks
    }
