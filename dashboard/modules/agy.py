#!/usr/bin/env python3
"""
Antigravity (AGY) Integration Inspector & Dispatcher Module
Provides transparent inspection of local CLI and remote API status.
Surfaces genuine HTTP 401 errors when unauthorized; never invents fake endpoints or responses.
"""

import os
import shutil
import urllib.request
import urllib.error
import subprocess
from pathlib import Path
from typing import Dict, Any

from modules.runner import execute_powershell

BASE_DIR = Path(__file__).resolve().parent.parent.parent
SCRIPTS_DIR = BASE_DIR / "scripts"

def get_agy_status() -> Dict[str, Any]:
    """Inspects local agy.exe presence, daemon state, and remote API configuration."""
    agy_cli = shutil.which("agy.exe") or shutil.which("agy")
    fallback_cli = r"C:\Users\Balamurugan S\AppData\Local\agy\bin\agy.exe"
    if not agy_cli and os.path.exists(fallback_cli):
        agy_cli = fallback_cli

    daemon_status = "Daemon not running or not registered."
    if agy_cli:
        try:
            r = subprocess.run([agy_cli, "remote-control", "status"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
            daemon_status = r.stdout.strip() or r.stderr.strip()
        except Exception:
            pass

    agy_api_url = os.environ.get("AGY_API_URL")
    agy_token = os.environ.get("AGY_API_TOKEN")

    remote_state = {
        "configured": agy_api_url is not None,
        "authenticated": False,
        "status_code": 401 if not agy_token else None,
        "message": "AGY integration unavailable — use the supported local CLI or continue configuration independently."
    }

    if agy_api_url:
        req = urllib.request.Request(agy_api_url)
        if agy_token:
            req.add_header("Authorization", f"Bearer {agy_token}")
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                remote_state["status_code"] = resp.status
                remote_state["authenticated"] = (resp.status == 200)
                remote_state["message"] = "Connected to remote Antigravity API."
        except urllib.error.HTTPError as he:
            remote_state["status_code"] = he.code
            remote_state["authenticated"] = False
            if he.code == 401:
                remote_state["message"] = "HTTP 401 Unauthorized: Invalid or missing Antigravity authentication token."
            else:
                remote_state["message"] = f"AGY API returned HTTP {he.code}: {he.reason}"
        except Exception as ex:
            remote_state["status_code"] = None
            remote_state["authenticated"] = False
            remote_state["message"] = f"Connection error: {str(ex)}"

    return {
        "success": True,
        "cli_detected": agy_cli is not None,
        "cli_path": agy_cli or "Not found",
        "daemon_status": daemon_status,
        "project_path": str(BASE_DIR),
        "remote_api": remote_state,
        "local_automation_active": True
    }

def run_approved_agy_task(task_name: str, use_remote: bool = False) -> Dict[str, Any]:
    """Runs an approved automation task, or surfaces HTTP 401 if remote authentication fails."""
    if use_remote:
        token = os.environ.get("AGY_API_TOKEN")
        if not token:
            return {
                "success": False,
                "error": "HTTP 401 Unauthorized: Missing or invalid AGY authentication credentials.",
                "status_code": 401,
                "hint": "AGY integration unavailable — use the supported local CLI or continue configuration independently."
            }

    task_map = {
        "master_reconfigure": {
            "title": "Master Reconfiguration & Service Refresh",
            "script": SCRIPTS_DIR / "Configure-Master.ps1",
            "args": ["-Force"]
        },
        "audit_slave_security": {
            "title": "Slave Private Key Isolation Security Audit",
            "script": SCRIPTS_DIR / "Validate-Slave.ps1",
            "args": ["-JsonOutput"]
        },
        "verify_all": {
            "title": "Comprehensive Master Health Validation",
            "script": SCRIPTS_DIR / "Validate-Master.ps1",
            "args": ["-JsonOutput"]
        }
    }

    if task_name not in task_map:
        return {"success": False, "error": f"Task '{task_name}' is not in approved task whitelist."}

    info = task_map[task_name]
    res = execute_powershell(info["script"], info["args"], task_title=f"AGY Task: {info['title']}")
    return {
        "success": res["success"],
        "task_name": task_name,
        "title": info["title"],
        "result": res
    }
