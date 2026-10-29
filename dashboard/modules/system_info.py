#!/usr/bin/env python3
"""
System Information and Status Inspector Module
"""

import os
import socket
import ctypes
import getpass
import platform
import subprocess
from typing import Dict, Any, List

from modules.veyon_cli import find_veyon_cli, get_veyon_version, get_auth_keys, is_server_process_running

def is_admin() -> bool:
    """Checks if process has elevated Administrator rights."""
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False

def check_port_listening(port: int = 11100, host: str = "127.0.0.1", timeout: float = 0.8) -> bool:
    """Attempts local socket connection to verify port is active."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((host, port))
        s.close()
        return True
    except Exception:
        return False

def get_service_status() -> Dict[str, Any]:
    """Queries Windows Service Control Manager for VeyonService."""
    try:
        cmd = ["powershell.exe", "-NoProfile", "-Command", "Get-Service -Name VeyonService -ErrorAction SilentlyContinue | Select-Object -Property Status, Name, DisplayName, StartType | ConvertTo-Json"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=8, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        if res.returncode == 0 and res.stdout.strip():
            import json
            data = json.loads(res.stdout.strip())
            status_map = {1: "Stopped", 2: "StartPending", 3: "StopPending", 4: "Running", 5: "ContinuePending", 6: "PausePending", 7: "Paused"}
            status_val = data.get("Status")
            status_str = status_map.get(status_val, str(status_val))
            return {
                "installed": True,
                "status": status_str,
                "display_name": data.get("DisplayName", "Veyon Service"),
                "start_type": data.get("StartType", "Automatic")
            }
    except Exception:
        pass
    return {"installed": False, "status": "Not Installed", "display_name": "Veyon Service", "start_type": "None"}

def get_network_interfaces() -> List[Dict[str, str]]:
    """Retrieves active network interfaces and IP addresses."""
    interfaces = []
    try:
        cmd = ["powershell.exe", "-NoProfile", "-Command", "Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*','Ethernet*','Local Area*' -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, IPAddress, PrefixLength | ConvertTo-Json"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=8, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        if res.returncode == 0 and res.stdout.strip():
            import json
            data = json.loads(res.stdout.strip())
            if isinstance(data, dict):
                data = [data]
            for item in data:
                ip = item.get("IPAddress")
                if ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                    interfaces.append({
                        "name": item.get("InterfaceAlias", "Ethernet"),
                        "ip": ip,
                        "prefix": item.get("PrefixLength", 24)
                    })
    except Exception:
        pass
    
    # Fallback
    if not interfaces:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            interfaces.append({"name": "Primary Adapter", "ip": s.getsockname()[0], "prefix": 24})
            s.close()
        except Exception:
            interfaces.append({"name": "Loopback", "ip": "127.0.0.1", "prefix": 8})

    return interfaces

def get_system_overview() -> Dict[str, Any]:
    """Generates complete live system overview."""
    cli_path = find_veyon_cli()
    version = get_veyon_version(cli_path)
    keys = get_auth_keys(cli_path)
    svc = get_service_status()
    server_running = is_server_process_running()
    port_listening = check_port_listening(11100)
    admin_status = is_admin()
    interfaces = get_network_interfaces()

    # Determine role
    has_priv = any("private" in k for k in keys)
    has_pub = any("public" in k for k in keys)
    role_detected = "Master" if has_priv else ("Slave" if has_pub else "Unconfigured")

    return {
        "hostname": socket.gethostname(),
        "username": getpass.getuser(),
        "is_admin": admin_status,
        "privilege_level": "Administrator (Elevated)" if admin_status else "Standard User (Non-Elevated)",
        "os_platform": platform.platform(),
        "windows_version": platform.version(),
        "veyon_installed": cli_path is not None,
        "veyon_cli_path": cli_path or "Not found",
        "veyon_version": version,
        "role_detected": role_detected,
        "installed_keys": keys,
        "service": svc,
        "server_process_running": server_running,
        "port_11100_listening": port_listening,
        "network_interfaces": interfaces
    }
