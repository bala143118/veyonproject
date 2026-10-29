#!/usr/bin/env python3
"""
Database Persistence Layer for VEYON OPS
SQLite storage for audit logs, client records, job execution history, and configuration backups.
"""

import os
import sqlite3
import getpass
import json
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple

DB_PATH = Path(__file__).resolve().parent / "veyon_ops.db"

def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH), timeout=15)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with get_connection() as conn:
        cursor = conn.cursor()
        
        # 1. Audit Logs Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                operation TEXT NOT NULL,
                computer TEXT NOT NULL,
                role TEXT NOT NULL,
                outcome TEXT NOT NULL,
                level TEXT NOT NULL,
                details TEXT,
                user TEXT NOT NULL
            )
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_audit_level ON audit_logs(level)")

        # 2. Clients (Slaves) Inventory Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS clients (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                host TEXT NOT NULL UNIQUE,
                mac TEXT,
                room_name TEXT NOT NULL DEFAULT 'Default Classroom',
                role TEXT NOT NULL DEFAULT 'Slave',
                status TEXT NOT NULL DEFAULT 'UNKNOWN',
                last_seen TEXT,
                last_check_result TEXT,
                last_check_timestamp TEXT,
                ping_ms REAL DEFAULT -1,
                port_open INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_client_host ON clients(host)")

        # 3. Configuration Backups Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS backups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                profile_name TEXT NOT NULL,
                filepath TEXT NOT NULL,
                filesize INTEGER NOT NULL DEFAULT 0,
                description TEXT
            )
        """)

        # 4. Job History Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                task_type TEXT NOT NULL,
                target TEXT,
                status TEXT NOT NULL,
                exit_code INTEGER,
                stdout TEXT,
                stderr TEXT,
                execution_time REAL DEFAULT 0
            )
        """)

        conn.commit()

# =========================================================
# AUDIT LOGS
# =========================================================

def add_audit_log(operation: str, outcome: str = "SUCCESS", level: str = "INFO", details: str = "", computer: str = "", role: str = "", user: str = ""):
    if not computer:
        import socket
        computer = socket.gethostname()
    if not user:
        try:
            user = getpass.getuser()
        except Exception:
            user = "SYSTEM"

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Sanitize details - never log private keys or passwords
    safe_details = details or ""
    if "PRIVATE KEY" in safe_details:
        safe_details = "[REDACTED: PRIVATE KEY MATERIAL]"

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO audit_logs (timestamp, operation, computer, role, outcome, level, details, user)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (now_str, operation, computer, role, outcome.upper(), level.upper(), safe_details, user))
        conn.commit()
        return cursor.lastrowid

def get_audit_logs(limit: int = 100, offset: int = 0, level: Optional[str] = None, search: Optional[str] = None, exclude_ops: Optional[List[str]] = None) -> Tuple[List[Dict[str, Any]], int]:
    with get_connection() as conn:
        cursor = conn.cursor()
        
        query = "SELECT * FROM audit_logs WHERE 1=1"
        params = []

        if level and level.upper() != "ALL":
            query += " AND level = ?"
            params.append(level.upper())

        if exclude_ops:
            for op in exclude_ops:
                query += " AND operation != ?"
                params.append(op)

        if search:
            query += " AND (operation LIKE ? OR details LIKE ? OR computer LIKE ? OR user LIKE ?)"
            s_term = f"%{search}%"
            params.extend([s_term, s_term, s_term, s_term])

        # Count total
        count_query = query.replace("SELECT *", "SELECT COUNT(*)", 1)
        cursor.execute(count_query, params)
        total = cursor.fetchone()[0]

        query += " ORDER BY id DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        cursor.execute(query, params)
        rows = cursor.fetchall()
        logs = [dict(r) for r in rows]
        return logs, total

def clear_audit_logs():
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM audit_logs")
        conn.commit()
    add_audit_log("AUDIT_LOG_CLEAR", outcome="SUCCESS", level="INFO", details="Audit log history cleared by administrator.")

# =========================================================
# CLIENTS (SLAVES) MANAGEMENT
# =========================================================

def get_all_clients() -> List[Dict[str, Any]]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM clients ORDER BY room_name ASC, name ASC")
        return [dict(r) for r in cursor.fetchall()]

def add_or_update_client(client_id: str, name: str, host: str, mac: str = "", room_name: str = "Default Classroom", status: str = "UNKNOWN", ping_ms: float = -1, port_open: int = 0) -> Dict[str, Any]:
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO clients (id, name, host, mac, room_name, role, status, ping_ms, port_open, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 'Slave', ?, ?, ?, ?, ?)
            ON CONFLICT(host) DO UPDATE SET
                name=excluded.name,
                mac=excluded.mac,
                room_name=excluded.room_name,
                status=excluded.status,
                ping_ms=excluded.ping_ms,
                port_open=excluded.port_open,
                updated_at=excluded.updated_at
        """, (client_id, name, host, mac, room_name, status, ping_ms, port_open, now, now))
        conn.commit()

        cursor.execute("SELECT * FROM clients WHERE host = ?", (host,))
        row = cursor.fetchone()
        return dict(row) if row else {}

def update_client_status(host: str = "", client_id: str = "", status: str = "", ping_ms: float = -1, port_open: bool = False, last_result: str = ""):
    now = datetime.now().isoformat()
    with get_connection() as conn:
        cursor = conn.cursor()
        if client_id:
            cursor.execute("""
                UPDATE clients
                SET status = ?, ping_ms = ?, port_open = ?, last_check_result = ?, last_check_timestamp = ?, updated_at = ?
                WHERE id = ?
            """, (status, ping_ms, 1 if port_open else 0, last_result, now, now, client_id))
        else:
            cursor.execute("""
                UPDATE clients
                SET status = ?, ping_ms = ?, port_open = ?, last_check_result = ?, last_check_timestamp = ?, updated_at = ?
                WHERE host = ?
            """, (status, ping_ms, 1 if port_open else 0, last_result, now, now, host))
        conn.commit()

def delete_client(client_id: str) -> bool:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM clients WHERE id = ?", (client_id,))
        deleted = cursor.rowcount > 0
        conn.commit()
        return deleted

def sync_clients_from_json(master_json_path: Path):
    """Seed or synchronize client records from existing veyon-master.json."""
    if not master_json_path.exists():
        return
    try:
        with open(master_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        objs = data.get("BuiltinDirectory", {}).get("NetworkObjects", {}).get("JsonStoreArray", [])
        
        rooms = {}
        for o in objs:
            if o.get("Type") == 2:
                rooms[o.get("Uid")] = o.get("Name")

        for o in objs:
            if o.get("Type") == 3:
                c_id = o.get("Uid")
                name = o.get("Name", "Unnamed PC")
                host = o.get("HostAddress", "localhost")
                room = rooms.get(o.get("ParentUid"), "Default Classroom")
                add_or_update_client(c_id, name, host, room_name=room)
    except Exception as e:
        print(f"Warning: Could not sync clients from JSON: {e}")

# =========================================================
# BACKUPS & JOBS
# =========================================================

def add_backup_record(profile_name: str, filepath: str, filesize: int = 0, description: str = ""):
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO backups (timestamp, profile_name, filepath, filesize, description)
            VALUES (?, ?, ?, ?, ?)
        """, (now_str, profile_name, filepath, filesize, description))
        conn.commit()

def get_backups() -> List[Dict[str, Any]]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM backups ORDER BY id DESC")
        return [dict(r) for r in cursor.fetchall()]

def add_job_record(task_type: str, target: str, status: str, exit_code: int, stdout: str, stderr: str, execution_time: float):
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO jobs (timestamp, task_type, target, status, exit_code, stdout, stderr, execution_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (now_str, task_type, target, status, exit_code, stdout, stderr, execution_time))
        conn.commit()
        return cursor.lastrowid

def get_recent_jobs(limit: int = 20) -> List[Dict[str, Any]]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM jobs ORDER BY id DESC LIMIT ?", (limit,))
        return [dict(r) for r in cursor.fetchall()]

# Initialize on import
init_db()
