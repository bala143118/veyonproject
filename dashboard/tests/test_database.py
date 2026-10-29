#!/usr/bin/env python3
"""
Unit tests for the SQLite Database Persistence Layer.
"""

import sys
from pathlib import Path

# Add dashboard to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest
import sqlite3
import database


class TestDatabaseOperations:
    """Verifies SQLite tables, indexes, insertion, querying, and filtering."""

    def setup_method(self):
        database.init_db()

    def test_audit_log_flow(self):
        # 1. Add audit log
        log_id = database.add_audit_log(
            operation="UNIT_TEST_OP",
            outcome="SUCCESS",
            level="INFO",
            details="Unit test details text",
            user="TestRunner"
        )
        assert isinstance(log_id, int)
        assert log_id > 0

        # 2. Retrieve audit logs
        logs, total = database.get_audit_logs(limit=20, level="INFO")
        assert total > 0
        assert any(l["operation"] == "UNIT_TEST_OP" for l in logs)

        # 3. Retrieve with level filter that doesn't match
        err_logs, _ = database.get_audit_logs(limit=20, level="ERROR")
        assert not any(l["operation"] == "UNIT_TEST_OP" for l in err_logs)

    def test_client_inventory_flow(self):
        # Add client
        database.add_or_update_client(
            client_id="test-slave-99",
            name="Lab Workstation 99",
            host="192.168.10.99",
            mac="00:11:22:33:44:99",
            room_name="Lab A"
        )

        # Fetch clients
        clients = database.get_all_clients()
        target = next((c for c in clients if c["id"] == "test-slave-99"), None)
        assert target is not None
        assert target["name"] == "Lab Workstation 99"
        assert target["host"] == "192.168.10.99"
        assert target["room_name"] == "Lab A"

        # Update client status
        database.update_client_status(
            client_id="test-slave-99",
            status="CONNECTED",
            ping_ms=4.0,
            port_open=True,
            last_result="CONNECTED"
        )

        clients_after = database.get_all_clients()
        target_after = next((c for c in clients_after if c["id"] == "test-slave-99"), None)
        assert target_after["status"] == "CONNECTED"
        assert target_after["ping_ms"] == 4.0
        assert target_after["port_open"] == 1

        # Delete client
        del_ok = database.delete_client("test-slave-99")
        assert del_ok is True
        clients_final = database.get_all_clients()
        assert not any(c["id"] == "test-slave-99" for c in clients_final)

    def test_job_execution_record(self):
        job_id = database.add_job_record(
            task_type="Validate-Master",
            target="Local System",
            status="SUCCESS",
            exit_code=0,
            stdout="All checks passed",
            stderr="",
            execution_time=1.25
        )
        assert isinstance(job_id, int)
        assert job_id > 0

        jobs = database.get_recent_jobs(limit=10)
        assert any(j["id"] == job_id for j in jobs)
