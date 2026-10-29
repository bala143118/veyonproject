#!/usr/bin/env python3
"""
Secure Subprocess PowerShell Script Execution Module
Enforces strict script whitelisting, timeout enforcement, argument array passing,
and automatic audit logging in SQLite.
"""

import os
import time
import subprocess
from pathlib import Path
from typing import List, Dict, Any, Optional

from database import add_job_record, add_audit_log

ALLOWED_SCRIPTS = {
    "Configure-Master.ps1",
    "Configure-Slave.ps1",
    "Validate-Master.ps1",
    "Validate-Slave.ps1",
    "Test-VeyonConnectivity.ps1",
    "Export-VeyonProfile.ps1",
    "Restore-VeyonBackup.ps1",
    "Install-VeyonConfig.ps1",
    "Verify-VeyonConfig.ps1"
}

def execute_powershell(script_path: Path, args: List[str], timeout: int = 120, task_title: str = "Script Execution") -> Dict[str, Any]:
    """
    Safely invokes an approved PowerShell script with separate arguments.
    """
    if script_path.name not in ALLOWED_SCRIPTS:
        add_audit_log(
            operation="UNAUTHORIZED_SCRIPT_EXEC_ATTEMPT",
            outcome="FAILURE",
            level="ERROR",
            details=f"Blocked execution attempt of unapproved script: {script_path.name}"
        )
        return {
            "success": False,
            "exit_code": -403,
            "stdout": "",
            "stderr": f"Security violation: Script '{script_path.name}' is not in the approved script whitelist.",
            "execution_time_sec": 0
        }

    if not script_path.exists():
        return {
            "success": False,
            "exit_code": -404,
            "stdout": "",
            "stderr": f"Script not found at: {script_path}",
            "execution_time_sec": 0
        }

    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", str(script_path)
    ] + args

    start_time = time.time()
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
        elapsed = round(time.time() - start_time, 2)
        success = proc.returncode == 0

        # Record in jobs table
        add_job_record(
            task_type=script_path.stem,
            target="Local System",
            status="SUCCESS" if success else "FAILED",
            exit_code=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
            execution_time=elapsed
        )

        # Record in audit logs
        add_audit_log(
            operation=task_title,
            outcome="SUCCESS" if success else "FAILED",
            level="EXEC" if success else "ERROR",
            details=f"Exit code: {proc.returncode}. Execution time: {elapsed}s."
        )

        return {
            "success": success,
            "exit_code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "execution_time_sec": elapsed
        }

    except subprocess.TimeoutExpired:
        elapsed = round(time.time() - start_time, 2)
        add_audit_log(operation=task_title, outcome="TIMEOUT", level="ERROR", details=f"Timeout expired after {timeout}s.")
        return {
            "success": False,
            "exit_code": -2,
            "stdout": "",
            "stderr": f"Execution timed out after {timeout} seconds.",
            "execution_time_sec": elapsed
        }
    except Exception as e:
        elapsed = round(time.time() - start_time, 2)
        add_audit_log(operation=task_title, outcome="EXCEPTION", level="ERROR", details=str(e))
        return {
            "success": False,
            "exit_code": -3,
            "stdout": "",
            "stderr": str(e),
            "execution_time_sec": elapsed
        }
