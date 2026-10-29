#!/usr/bin/env python3
"""
VEYON OPS -- Enterprise Master/Slave Web Administration Dashboard Backend
Production-grade Flask server with persistent SQLite database, structured REST APIs,
safe PowerShell execution, and transparent AGY status inspection.
"""

import os
import io
import csv
import json
import socket
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List, Optional

from flask import Flask, render_template, request, jsonify, send_file, Response

# Module imports
from database import (
    init_db, add_audit_log, get_audit_logs, clear_audit_logs,
    get_all_clients, add_or_update_client, update_client_status, delete_client, sync_clients_from_json,
    add_backup_record, get_backups, add_job_record, get_recent_jobs
)
from modules.system_info import get_system_overview, is_admin, check_port_listening, get_service_status
from modules.veyon_cli import find_veyon_cli, get_veyon_version, get_supported_modules, get_auth_keys, is_server_process_running
from modules.connectivity import test_host_connectivity, validate_host
from modules.runner import execute_powershell
from modules.profiles import read_profile, validate_profile_json, compute_diff, save_profile_with_backup, PROFILES, CONFIG_DIR, BACKUPS_DIR
from modules.diagnostics import run_diagnostics
from modules.agy import get_agy_status, run_approved_agy_task

app = Flask(__name__, static_folder="static", template_folder="templates")

# Paths
BASE_DIR = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = BASE_DIR / "scripts"
KEYS_DIR = CONFIG_DIR / "keys"

# Initialize DB & Sync Clients
init_db()
sync_clients_from_json(CONFIG_DIR / "veyon-master.json")
add_audit_log("PLATFORM_STARTUP", outcome="SUCCESS", level="INFO", details="VEYON OPS Backend initialized.")

# Security headers middleware
@app.after_request
def add_security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    return response

# =========================================================
# 1. ROOT & OVERVIEW STATUS ENDPOINTS
# =========================================================

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/system/status", methods=["GET"])
@app.route("/api/status", methods=["GET"])
def api_status():
    overview = get_system_overview()
    clients = get_all_clients()
    
    total_clients = len(clients)
    connected_clients = sum(1 for c in clients if c.get("status") == "CONNECTED")

    overview["slave_count"] = total_clients
    overview["connected_slaves"] = connected_clients
    overview["success"] = True
    overview["timestamp"] = datetime.now().isoformat()
    return jsonify(overview)

@app.route("/api/veyon/status", methods=["GET"])
def api_veyon_status():
    cli_path = find_veyon_cli()
    version = get_veyon_version(cli_path)
    modules = get_supported_modules(cli_path)
    keys = get_auth_keys(cli_path)
    svc = get_service_status()
    server_running = is_server_process_running()

    return jsonify({
        "success": True,
        "installed": cli_path is not None,
        "cli_path": cli_path or "Not found",
        "version": version,
        "supported_modules": modules,
        "installed_keys": keys,
        "service": svc,
        "server_process_running": server_running,
        "server_status": "RUNNING" if server_running else ("SERVICE ACTIVE" if svc["status"] == "Running" else "INACTIVE")
    })

# =========================================================
# 2. MASTER CONFIGURATION & PREVIEW ENDPOINTS
# =========================================================

@app.route("/api/master/preview", methods=["POST"])
def api_master_preview():
    payload = request.get_json(silent=True) or {}
    key_name = payload.get("key_name", "teacher").strip()
    room_name = payload.get("room_name", "Default Classroom").strip()
    client_hosts = payload.get("client_hosts", [])

    # Validate inputs
    valid_key, clean_key = validate_host(key_name)
    if not valid_key:
        return jsonify({"success": False, "error": f"Invalid key name: {clean_key}"}), 400

    validated_hosts = []
    for h in client_hosts:
        h_str = str(h).strip()
        v, res = validate_host(h_str)
        if v:
            validated_hosts.append(res)

    preview_details = {
        "key_pair": {
            "name": clean_key,
            "private_key": f"{clean_key}/private (Restricted to Administrators only)",
            "public_key": f"{clean_key}/public (Exported for Slave deployment)"
        },
        "classroom": {
            "name": room_name,
            "clients_to_register": validated_hosts
        },
        "settings_to_enforce": {
            "Authentication/Method": 1,
            "Windows/SoftwareSASEnabled": 1,
            "Service/SoftwareSASEnabled": 0,
            "Network/FirewallExceptionEnabled": 1,
            "Network/VeyonServerPort": 11100,
            "ForceGuest": 0
        },
        "service_action": "Register VeyonService, set Startup to Automatic, restart service"
    }

    return jsonify({"success": True, "preview": preview_details})

@app.route("/api/master/configure", methods=["POST"])
def api_master_configure():
    payload = request.get_json(silent=True) or {}
    key_name = payload.get("key_name", "teacher").strip()
    room_name = payload.get("room_name", "Default Classroom").strip()
    client_hosts = payload.get("client_hosts", [])
    force = bool(payload.get("force", False))

    valid_key, clean_key = validate_host(key_name)
    if not valid_key:
        return jsonify({"success": False, "error": f"Invalid key name: {clean_key}"}), 400

    args = ["-KeyName", clean_key]
    if room_name:
        args.extend(["-RoomName", room_name])

    clean_hosts = []
    for ch in client_hosts:
        v, h = validate_host(str(ch).strip())
        if v:
            clean_hosts.append(h)
            args.extend(["-ClientHosts", h])

    if force:
        args.append("-Force")
    args.append("-JsonOutput")

    script_path = SCRIPTS_DIR / "Configure-Master.ps1"
    res = execute_powershell(script_path, args, task_title=f"Master Configuration ({clean_key})")

    # If successful, register any new client hosts in database as well
    if res["success"]:
        import uuid
        for h in clean_hosts:
            cid = "{" + str(uuid.uuid4()) + "}"
            add_or_update_client(cid, h, h, room_name=room_name)

    return jsonify(res)

@app.route("/api/master/validate", methods=["POST"])
def api_master_validate():
    payload = request.get_json(silent=True) or {}
    key_name = payload.get("key_name", "teacher").strip()
    valid_key, clean_key = validate_host(key_name)
    if not valid_key:
        clean_key = "teacher"

    script_path = SCRIPTS_DIR / "Validate-Master.ps1"
    res = execute_powershell(script_path, ["-KeyName", clean_key, "-JsonOutput"], task_title="Validate Master Health")
    return jsonify(res)

# =========================================================
# 3. SLAVE MANAGEMENT ENDPOINTS
# =========================================================

@app.route("/api/clients", methods=["GET", "POST"])
def api_clients():
    if request.method == "GET":
        clients = get_all_clients()
        return jsonify({"success": True, "count": len(clients), "clients": clients})

    elif request.method == "POST":
        payload = request.get_json(silent=True) or {}
        name = str(payload.get("name", "")).strip()
        host = str(payload.get("host", "")).strip()
        room = str(payload.get("room_name", "Default Classroom")).strip()
        mac = str(payload.get("mac", "")).strip()

        if not name:
            return jsonify({"success": False, "error": "Computer name is required."}), 400
        valid, clean_host = validate_host(host)
        if not valid:
            return jsonify({"success": False, "error": f"Invalid host: {clean_host}"}), 400

        import uuid
        client_id = payload.get("id") or ("{" + str(uuid.uuid4()) + "}")

        client_rec = add_or_update_client(client_id, name, clean_host, mac=mac, room_name=room)

        # Also sync to veyon-master.json network objects
        try:
            m_path = CONFIG_DIR / "veyon-master.json"
            if m_path.exists():
                with open(m_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                array = data.setdefault("BuiltinDirectory", {}).setdefault("NetworkObjects", {}).setdefault("JsonStoreArray", [])
                
                # Check room
                room_obj = next((o for o in array if o.get("Type") == 2 and o.get("Name") == room), None)
                if not room_obj:
                    room_uid = "{" + str(uuid.uuid4()) + "}"
                    room_obj = {"Name": room, "Type": 2, "Uid": room_uid}
                    array.append(room_obj)

                # Add or update computer
                comp_obj = next((o for o in array if o.get("Type") == 3 and o.get("HostAddress") == clean_host), None)
                if comp_obj:
                    comp_obj["Name"] = name
                    comp_obj["ParentUid"] = room_obj["Uid"]
                else:
                    array.append({
                        "HostAddress": clean_host,
                        "Name": name,
                        "ParentUid": room_obj["Uid"],
                        "Type": 3,
                        "Uid": client_id
                    })
                with open(m_path, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=4)
        except Exception as ex:
            print(f"Warning syncing master.json: {ex}")

        add_audit_log(
            operation="CLIENT_REGISTER",
            outcome="SUCCESS",
            level="INFO",
            details=f"Registered client '{name}' ({clean_host}) in '{room}'."
        )
        return jsonify({"success": True, "client": client_rec})

@app.route("/api/clients/<client_id>", methods=["DELETE"])
def api_delete_client(client_id: str):
    client_id = client_id.strip()
    deleted = delete_client(client_id)
    
    # Also remove from veyon-master.json
    try:
        m_path = CONFIG_DIR / "veyon-master.json"
        if m_path.exists():
            with open(m_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            array = data.get("BuiltinDirectory", {}).get("NetworkObjects", {}).get("JsonStoreArray", [])
            new_array = [o for o in array if o.get("Uid") != client_id]
            data["BuiltinDirectory"]["NetworkObjects"]["JsonStoreArray"] = new_array
            with open(m_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4)
    except Exception:
        pass

    add_audit_log(
        operation="CLIENT_DELETE",
        outcome="SUCCESS" if deleted else "WARNING",
        level="INFO",
        details=f"Removed client record ID: {client_id}"
    )
    return jsonify({"success": deleted})

@app.route("/api/clients/validate", methods=["POST"])
def api_clients_validate():
    payload = request.get_json(silent=True) or {}
    target_hosts = payload.get("hosts", [])

    if not target_hosts:
        # Check all registered clients
        clients = get_all_clients()
        target_hosts = [c["host"] for c in clients]

    results = []
    for h in target_hosts:
        res = test_host_connectivity(h)
        update_client_status(
            host=res["host"],
            status=res["state"],
            ping_ms=res["ping_ms"],
            port_open=res["port_open"],
            last_result=res["state"]
        )
        results.append(res)

    add_audit_log(
        operation="CLIENT_CONNECTIVITY_SCAN",
        outcome="SUCCESS",
        level="INFO",
        details=f"Tested connectivity for {len(results)} client hosts."
    )
    return jsonify({"success": True, "results": results})

@app.route("/api/clients/generate-package", methods=["POST"])
def api_generate_package():
    payload = request.get_json(silent=True) or {}
    key_name = payload.get("key_name", "teacher").strip()
    hide_tray = bool(payload.get("hide_tray_icon", False))

    pub_key_path = KEYS_DIR / f"{key_name}_public_key.pem"
    if not pub_key_path.exists():
        pub_key_path = KEYS_DIR / "teacher_public_key.pem"

    pub_content = ""
    if pub_key_path.exists():
        with open(pub_key_path, "r", encoding="utf-8") as f:
            pub_content = f.read()

    # Generate one-line PowerShell command
    cmd_one_liner = f"powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -Uri 'http://{socket.gethostname()}:5000/api/keys/public?download=true' -OutFile '$env:TEMP\\teacher_public_key.pem'; .\\install.ps1 -Role Slave -PublicKeyPath '$env:TEMP\\teacher_public_key.pem'{' -HideTrayIcon' if hide_tray else ''}\""

    return jsonify({
        "success": True,
        "key_name": key_name,
        "public_key_present": bool(pub_content),
        "one_liner_command": cmd_one_liner,
        "instructions": [
            "1. Copy the Master public key or ensure the student PC can access http://master-ip:5000/api/keys/public.",
            "2. Open Windows PowerShell as Administrator on the student PC.",
            "3. Run the generated command above to execute Configure-Slave.ps1.",
            "4. The installer automatically purges any private keys on the student PC and starts VeyonService."
        ]
    })

@app.route("/api/clients/remote-deploy", methods=["POST"])
def api_remote_deploy():
    """
    WinRM Remote Deployment endpoint.
    Strictly verifies that a legitimate remote transport is available before attempting.
    Does NOT pretend Veyon has a magic remote deployment mechanism without transport.
    """
    payload = request.get_json(silent=True) or {}
    target_host = payload.get("host", "").strip()

    valid, clean_host = validate_host(target_host)
    if not valid:
        return jsonify({"success": False, "error": f"Invalid target host: {clean_host}"}), 400

    # Test WinRM port 5985
    winrm_active = check_port_listening(5985, host=clean_host, timeout=1.0)
    if not winrm_active:
        return jsonify({
            "success": False,
            "transport_available": False,
            "error": f"WinRM transport (TCP 5985) is not reachable on '{clean_host}'.",
            "explanation": "Remote automated client configuration requires Windows Remote Management (WinRM) to be enabled on the target client machine.",
            "remediation": "To deploy to this client, either enable WinRM on the client ('winrm quickconfig') or use the Local Client Setup one-liner on that machine."
        }), 400

    return jsonify({
        "success": False,
        "transport_available": True,
        "error": "WinRM credentials required.",
        "remediation": "Provide administrative credentials for WinRM remoting to proceed."
    }), 401

# =========================================================
# 4. CONFIGURATION PROFILES & BACKUPS
# =========================================================

@app.route("/api/profiles", methods=["GET"])
def api_profiles_list():
    profiles_data = []
    for name, p in PROFILES.items():
        exists = p.exists()
        size = p.stat().st_size if exists else 0
        profiles_data.append({
            "name": name,
            "filename": p.name,
            "path": str(p),
            "exists": exists,
            "size_bytes": size
        })

    backups = get_backups()
    return jsonify({"success": True, "profiles": profiles_data, "backups": backups})

@app.route("/api/profiles/<profile_name>", methods=["GET", "POST"])
def api_profile_detail(profile_name: str):
    if request.method == "GET":
        ok, data, path_or_err = read_profile(profile_name)
        if not ok:
            return jsonify({"success": False, "error": path_or_err}), 404
        return jsonify({"success": True, "profile": profile_name, "path": path_or_err, "data": data})

    elif request.method == "POST":
        payload = request.get_json(silent=True)
        if not payload or not isinstance(payload, dict):
            return jsonify({"success": False, "error": "Invalid JSON object provided."}), 400

        ok, msg = save_profile_with_backup(profile_name, payload)
        if not ok:
            return jsonify({"success": False, "error": msg}), 500
        return jsonify({"success": True, "message": msg})

@app.route("/api/profiles/<profile_name>/diff", methods=["POST"])
@app.route("/api/profiles/diff", methods=["POST"])
def api_profile_diff(profile_name: str = ""):
    payload = request.get_json(silent=True) or {}
    p_name = profile_name or payload.get("profile_name", "master")
    proposed_text = payload.get("content", "") or payload.get("modified_content", "")
    diff_text = compute_diff(p_name, proposed_text)
    return jsonify({"success": True, "profile": p_name, "diff": diff_text})

@app.route("/api/profiles/<profile_name>/apply", methods=["POST"])
def api_profile_apply(profile_name: str):
    """Applies profile to live Veyon system after taking a pre-apply backup."""
    target_path = PROFILES.get(profile_name.lower())
    if not target_path or not target_path.exists():
        return jsonify({"success": False, "error": f"Profile '{profile_name}' not found."}), 404

    cli_path = find_veyon_cli()
    if not cli_path:
        return jsonify({"success": False, "error": "Veyon CLI not installed."}), 400

    # Safety backup first
    export_script = SCRIPTS_DIR / "Export-VeyonProfile.ps1"
    execute_powershell(export_script, ["-ProfileName", f"pre-apply-{profile_name}"], task_title="Pre-Apply Configuration Backup")

    # Import
    res = execute_powershell(
        SCRIPTS_DIR / "Restore-VeyonBackup.ps1",
        ["-BackupFile", str(target_path)],
        task_title=f"Apply Profile: {profile_name}"
    )
    return jsonify(res)

@app.route("/api/profiles/restore", methods=["POST"])
def api_profile_restore():
    payload = request.get_json(silent=True) or {}
    backup_file = payload.get("backup_file", "").strip()

    if not backup_file or not os.path.exists(backup_file):
        return jsonify({"success": False, "error": f"Backup file not found: {backup_file}"}), 404

    res = execute_powershell(
        SCRIPTS_DIR / "Restore-VeyonBackup.ps1",
        ["-BackupFile", backup_file],
        task_title="Restore Configuration Backup"
    )
    return jsonify(res)

# =========================================================
# 5. AGY TASK CENTER
# =========================================================

@app.route("/api/agy/status", methods=["GET"])
def api_get_agy_status():
    status = get_agy_status()
    return jsonify(status)

@app.route("/api/agy/task", methods=["POST"])
@app.route("/api/agy/run-task", methods=["POST"])
def api_dispatch_agy_task():
    payload = request.get_json(silent=True) or {}
    task_name = payload.get("task_name", "").strip()
    use_remote = bool(payload.get("use_remote_agy", False) or payload.get("use_remote", False))

    res = run_approved_agy_task(task_name, use_remote=use_remote)
    status_code = res.get("status_code", 200)
    return jsonify(res), status_code

# =========================================================
# 6. DIAGNOSTICS & LOGS
# =========================================================

@app.route("/api/diagnostics", methods=["GET"])
@app.route("/api/diagnostics/run", methods=["GET"])
def api_run_diagnostics():
    diag = run_diagnostics()
    add_audit_log(
        operation="SYSTEM_DIAGNOSTICS_RUN",
        outcome="SUCCESS" if diag["failed"] == 0 else "WARNING",
        level="INFO",
        details=f"Diagnostics: {diag['passed']}/{diag['total']} passed, {diag['failed']} failed."
    )
    return jsonify(diag)

@app.route("/api/audit-logs", methods=["GET", "DELETE"])
@app.route("/api/logs", methods=["GET", "DELETE"])
def api_audit_logs():
    if request.method == "GET":
        level = request.args.get("level", "ALL")
        search = request.args.get("search", None)
        limit = min(int(request.args.get("limit", 100)), 500)
        offset = int(request.args.get("offset", 0))
        exclude_raw = request.args.get("exclude_ops", "")
        exclude_list = [x.strip() for x in exclude_raw.split(",") if x.strip()] if exclude_raw else None

        logs, total = get_audit_logs(limit=limit, offset=offset, level=level, search=search, exclude_ops=exclude_list)
        return jsonify({
            "success": True,
            "total": total,
            "limit": limit,
            "offset": offset,
            "logs": logs
        })

    elif request.method == "DELETE":
        clear_audit_logs()
        return jsonify({"success": True, "message": "Audit logs cleared."})

@app.route("/api/audit-logs/export", methods=["GET"])
def api_audit_logs_export():
    logs, _ = get_audit_logs(limit=10000, offset=0, level="ALL")
    
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Timestamp", "Operation", "Computer", "Role", "Outcome", "Level", "Details", "User"])
    
    for l in logs:
        writer.writerow([
            l["id"], l["timestamp"], l["operation"], l["computer"],
            l["role"], l["outcome"], l["level"], l["details"], l["user"]
        ])

    output.seek(0)
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment;filename=veyon_audit_logs_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"}
    )

# =========================================================
# 7. SERVICE & SECURITY CONTROLS
# =========================================================

@app.route("/api/service/restart", methods=["POST"])
@app.route("/api/action/run-script", methods=["POST"])
def api_service_action():
    payload = request.get_json(silent=True) or {}
    action = payload.get("action")

    if action == "restart_service" or request.path == "/api/service/restart":
        if not is_admin():
            return jsonify({
                "success": False,
                "error": "Administrator privileges required to restart Veyon Windows Service.",
                "requires_elevation": True
            }), 403

        cli = find_veyon_cli()
        cmd = [cli, "service", "restart"] if cli else ["powershell.exe", "-Command", "Restart-Service VeyonService -Force"]
        try:
            import subprocess
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
            success = r.returncode == 0
            add_audit_log(
                operation="SERVICE_RESTART",
                outcome="SUCCESS" if success else "FAILURE",
                level="EXEC" if success else "ERROR",
                details=r.stderr or r.stdout
            )
            return jsonify({"success": success, "stdout": r.stdout, "stderr": r.stderr})
        except Exception as e:
            add_audit_log(operation="SERVICE_RESTART", outcome="EXCEPTION", level="ERROR", details=str(e))
            return jsonify({"success": False, "error": str(e)}), 500

    elif action == "master_setup":
        return api_master_configure()
    elif action == "verify":
        return api_master_validate()

    return jsonify({"success": False, "error": f"Unknown action: {action}"}), 400

@app.route("/api/action/test-connectivity", methods=["POST"])
def api_test_conn_compat():
    payload = request.get_json(silent=True) or {}
    host = str(payload.get("host", "")).strip()
    port = int(payload.get("port", 11100))
    res = test_host_connectivity(host, port)
    res["success"] = True
    return jsonify(res)

@app.route("/api/network-objects", methods=["GET", "POST"])
def api_net_objs_compat():
    if request.method == "GET":
        m_path = CONFIG_DIR / "veyon-master.json"
        try:
            with open(m_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            objs = data.get("BuiltinDirectory", {}).get("NetworkObjects", {}).get("JsonStoreArray", [])
            return jsonify({"success": True, "objects": objs})
        except Exception as e:
            return jsonify({"success": False, "error": str(e), "objects": []}), 500
    else:
        return api_clients()

@app.route("/api/keys/public", methods=["GET"])
def api_public_key():
    """Provides public key download for distributing to Slave PCs. Private keys are NEVER exposed."""
    pub_file = KEYS_DIR / "teacher_public_key.pem"
    if not pub_file.exists():
        pub_file = KEYS_DIR / "default_public_key.pem"

    if not pub_file.exists():
        return jsonify({"success": False, "error": "Public key file not found. Run Master setup to export key."}), 404

    as_attachment = request.args.get("download", "false").lower() == "true"
    if as_attachment:
        return send_file(pub_file, as_attachment=True, download_name="teacher_public_key.pem")
    else:
        with open(pub_file, "r", encoding="utf-8") as f:
            content = f.read()
        return jsonify({"success": True, "filename": pub_file.name, "content": content})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"\n=======================================================")
    print(f"  VEYON OPS -- Administration Dashboard Backend")
    print(f"  Listening on: http://127.0.0.1:{port}")
    print(f"  Privilege Level: {'[ADMINISTRATOR]' if is_admin() else '[STANDARD USER - Run as Admin for service changes]'}")
    print(f"=======================================================\n")
    app.run(host="127.0.0.1", port=port, debug=False)
