#!/usr/bin/env python3
"""
Configuration Profiles Manager
Handles JSON reading, writing, syntax validation, unified diffing, and versioned backups.
"""

import json
import difflib
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Tuple, Optional, List

from database import add_backup_record, add_audit_log, get_backups

BASE_DIR = Path(__file__).resolve().parent.parent.parent
CONFIG_DIR = BASE_DIR / "config"
BACKUPS_DIR = CONFIG_DIR / "backups"

PROFILES = {
    "master": CONFIG_DIR / "veyon-master.json",
    "slave": CONFIG_DIR / "veyon-slave.json",
    "unified": CONFIG_DIR / "veyon-unified.json"
}

def get_profile_path(profile_name: str) -> Optional[Path]:
    return PROFILES.get(profile_name.lower())

def read_profile(profile_name: str) -> Tuple[bool, Any, str]:
    target_path = get_profile_path(profile_name)
    if not target_path or not target_path.exists():
        return False, None, f"Profile '{profile_name}' not found."

    try:
        with open(target_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return True, data, str(target_path)
    except Exception as e:
        return False, None, f"Failed reading JSON: {str(e)}"

def validate_profile_json(json_str: str) -> Tuple[bool, Optional[Dict[str, Any]], str]:
    """Validates JSON syntax and checks for essential Veyon properties."""
    try:
        obj = json.loads(json_str)
    except json.JSONDecodeError as jde:
        return False, None, f"JSON Syntax Error at line {jde.lineno}, column {jde.colno}: {jde.msg}"
    except Exception as e:
        return False, None, f"Malformed JSON: {str(e)}"

    if not isinstance(obj, dict):
        return False, None, "Root element of Veyon profile must be a JSON object"

    # Schema checks
    if "Authentication" in obj:
        auth = obj["Authentication"]
        if not isinstance(auth, dict):
            return False, None, "Authentication section must be an object"
        if "Method" in auth and auth["Method"] not in [0, 1, "0", "1"]:
            return False, None, "Authentication.Method must be 0 (Logon) or 1 (Key File)"

    return True, obj, "JSON syntax and structure are valid."

def compute_diff(profile_name: str, new_content: str) -> str:
    """Computes unified diff between current disk file and proposed text."""
    target_path = get_profile_path(profile_name)
    if not target_path or not target_path.exists():
        return "File does not exist on disk."

    try:
        with open(target_path, "r", encoding="utf-8") as f:
            original_lines = f.readlines()
        new_lines = [l + "\n" for l in new_content.splitlines()]

        diff = difflib.unified_diff(
            original_lines,
            new_lines,
            fromfile=f"a/{target_path.name}",
            tofile=f"b/{target_path.name}",
            lineterm=""
        )
        return "\n".join(diff) or "No changes detected."
    except Exception as e:
        return f"Diff generation error: {str(e)}"

def save_profile_with_backup(profile_name: str, new_dict: Dict[str, Any], user: str = "Admin") -> Tuple[bool, str]:
    """Saves profile JSON, automatically generating a pre-save backup in config/backups/."""
    target_path = get_profile_path(profile_name)
    if not target_path:
        return False, f"Unknown profile: {profile_name}"

    if not BACKUPS_DIR.exists():
        BACKUPS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Create Pre-Save Backup
    if target_path.exists():
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_filename = f"backup-{profile_name}-{timestamp}.json"
        backup_path = BACKUPS_DIR / backup_filename
        try:
            with open(target_path, "r", encoding="utf-8") as f_src:
                content = f_src.read()
            with open(backup_path, "w", encoding="utf-8") as f_dst:
                f_dst.write(content)
            add_backup_record(profile_name, str(backup_path), len(content), f"Auto-backup before editing {profile_name}")
        except Exception as e:
            print(f"Warning: Could not create backup: {e}")

    # 2. Write New Profile
    try:
        with open(target_path, "w", encoding="utf-8") as f:
            json.dump(new_dict, f, indent=4)
        
        add_audit_log(
            operation="PROFILE_SAVE",
            outcome="SUCCESS",
            level="INFO",
            details=f"Updated profile '{profile_name}.json' on disk.",
            user=user
        )
        return True, f"Profile '{profile_name}' saved successfully."
    except Exception as e:
        add_audit_log(
            operation="PROFILE_SAVE",
            outcome="FAILURE",
            level="ERROR",
            details=f"Failed saving profile '{profile_name}': {str(e)}",
            user=user
        )
        return False, f"Failed writing to disk: {str(e)}"
