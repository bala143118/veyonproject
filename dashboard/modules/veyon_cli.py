#!/usr/bin/env python3
"""
Veyon CLI and Process Inspector Module
"""

import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional, List, Dict, Any

def find_veyon_cli() -> Optional[str]:
    """Auto-detect Veyon CLI executable."""
    candidates = [
        r"C:\Program Files\Veyon\veyon-cli.exe",
        r"C:\Program Files (x86)\Veyon\veyon-cli.exe",
        r"C:\Program Files\Veyon\veyon-wcli.exe",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    
    cli_in_path = shutil.which("veyon-cli.exe") or shutil.which("veyon-cli")
    if cli_in_path:
        return cli_in_path
    return None

def get_veyon_version(cli_path: Optional[str] = None) -> str:
    """Attempts to determine the installed Veyon version."""
    if not cli_path:
        cli_path = find_veyon_cli()
    if not cli_path or not os.path.exists(cli_path):
        return "Not Installed"

    # 1. Try powershell file version info
    try:
        cmd = ["powershell.exe", "-NoProfile", "-Command", f"(Get-Item '{cli_path}').VersionInfo.FileVersion"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        v = res.stdout.strip()
        if v:
            return v
    except Exception:
        pass

    # 2. Try veyon-cli --version or -v
    try:
        res = subprocess.run([cli_path, "--version"], stdout=subprocess.PIPE, text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        line = res.stdout.strip().splitlines()
        if line:
            return line[0].strip()
    except Exception:
        pass

    return "4.8.x"

def get_supported_modules(cli_path: Optional[str] = None) -> List[str]:
    """Queries CLI help to list supported modules."""
    if not cli_path:
        cli_path = find_veyon_cli()
    if not cli_path or not os.path.exists(cli_path):
        return []

    try:
        res = subprocess.run([cli_path, "help"], stdout=subprocess.PIPE, text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        modules = []
        for line in res.stdout.splitlines():
            line = line.strip()
            if line and " - " in line:
                mod = line.split(" - ")[0].strip()
                if mod and " " not in mod:
                    modules.append(mod)
        return modules
    except Exception:
        return ["config", "authkeys", "service", "networkobjects"]

def get_auth_keys(cli_path: Optional[str] = None) -> List[str]:
    """Queries veyon-cli authkeys list."""
    if not cli_path:
        cli_path = find_veyon_cli()
    if not cli_path or not os.path.exists(cli_path):
        return []

    try:
        res = subprocess.run(
            [cli_path, "authkeys", "list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        keys = []
        for line in res.stdout.splitlines():
            line = line.strip()
            if line and not line.startswith("[") and not line.startswith("Available"):
                keys.append(line)
        return keys
    except Exception:
        return []

def get_config_value(key: str, cli_path: Optional[str] = None) -> Optional[str]:
    """Reads a single configuration property using veyon-cli config get <key>."""
    if not cli_path:
        cli_path = find_veyon_cli()
    if not cli_path or not os.path.exists(cli_path):
        return None

    try:
        res = subprocess.run(
            [cli_path, "config", "get", key],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        for line in res.stdout.splitlines():
            line = line.strip()
            if line and not line.startswith("[") and not line.startswith("Available"):
                return line
    except Exception:
        pass
    return None

def is_server_process_running() -> bool:
    """Checks if veyon-server.exe process is currently running on the system."""
    try:
        res = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", "(Get-Process -Name 'veyon-server' -ErrorAction SilentlyContinue).Count"],
            stdout=subprocess.PIPE,
            text=True,
            timeout=5,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        count = res.stdout.strip()
        return int(count) > 0 if count.isdigit() else False
    except Exception:
        return False
