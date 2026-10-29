#!/usr/bin/env python3
"""
Comprehensive integration tests for Flask REST APIs.
Uses Flask's test client to verify routes, validation, security headers, and status codes.
"""

import sys
import json
from pathlib import Path

# Add dashboard to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


class TestSecurityHeaders:
    """Verifies that security headers are enforced on all responses."""

    def test_security_headers_present(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        assert resp.headers.get("X-Content-Type-Options") == "nosniff"
        assert resp.headers.get("X-Frame-Options") == "SAMEORIGIN"
        assert resp.headers.get("X-XSS-Protection") == "1; mode=block"


class TestSystemAndVeyonStatusAPIs:
    """Tests overview, system inspection, and Veyon discovery APIs."""

    def test_dashboard_index(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        assert b"VEYON OPS" in resp.data

    def test_system_status(self, client):
        resp = client.get("/api/system/status")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "hostname" in data
        assert "is_admin" in data
        assert "role_detected" in data
        assert "service" in data

    def test_veyon_status(self, client):
        resp = client.get("/api/veyon/status")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "installed" in data
        assert "installed_keys" in data
        assert isinstance(data["installed_keys"], list)


class TestClientManagementAPIs:
    """Tests client inventory CRUD, validation, and connectivity probing."""

    def test_get_clients(self, client):
        resp = client.get("/api/clients")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "clients" in data
        assert isinstance(data["clients"], list)

    def test_add_client_with_illegal_characters(self, client):
        payload = {
            "name": "Malicious Host",
            "host": "192.168.1.50; calc.exe",
            "room_name": "Lab A"
        }
        resp = client.post("/api/clients", json=payload)
        assert resp.status_code == 400
        data = resp.get_json()
        assert data["success"] is False
        assert "illegal metacharacters" in data["error"].lower() or "invalid" in data["error"].lower()

    def test_add_client_success_and_delete(self, client):
        payload = {
            "name": "AutoTest Slave 01",
            "host": "10.0.99.201",
            "mac": "00:AA:BB:CC:DD:EE",
            "room_name": "Testing Lab"
        }
        # 1. Add
        resp = client.post("/api/clients", json=payload)
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        client_id = data["client"]["id"]

        # 2. Verify in list
        list_resp = client.get("/api/clients")
        clients = list_resp.get_json()["clients"]
        matched = next((c for c in clients if c["id"] == client_id), None)
        assert matched is not None
        assert matched["host"] == "10.0.99.201"

        # 3. Delete
        del_resp = client.delete(f"/api/clients/{client_id}")
        assert del_resp.status_code == 200
        assert del_resp.get_json()["success"] is True

    def test_validate_single_client_endpoint(self, client):
        payload = {"hosts": ["127.0.0.1"]}
        resp = client.post("/api/clients/validate", json=payload)
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert len(data["results"]) == 1
        res0 = data["results"][0]
        # Explicit state must be one of the recognized states
        assert res0["state"] in [
            "CONNECTED", "DISCONNECTED", "PORT_OPEN_PING_BLOCKED",
            "PING_REPLIED_PORT_CLOSED", "CHECK FAILED"
        ]


class TestConfigurationProfilesAPIs:
    """Tests profile reading, diff computation, and validation."""

    def test_get_profiles(self, client):
        resp = client.get("/api/profiles")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "profiles" in data
        assert any(p["name"] == "master" for p in data["profiles"])
        assert any(p["name"] == "slave" for p in data["profiles"])

    def test_get_master_profile_content(self, client):
        resp = client.get("/api/profiles/master")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "profile" in data
        assert "data" in data

    def test_compute_profile_diff(self, client):
        resp = client.post("/api/profiles/diff", json={
            "profile_name": "master",
            "content": "{\n  \"ModifiedKey\": \"Test\"\n}"
        })
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "diff" in data

    def test_validate_master_preview(self, client):
        resp = client.post("/api/master/preview", json={
            "profile_name": "master",
            "room_name": "Physics Lab",
            "key_name": "teacher"
        })
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert data["preview"]["classroom"]["name"] == "Physics Lab"


class TestDiagnosticsAndAuditLogsAPIs:
    """Tests 10-point diagnostic engine and persistent audit logging."""

    def test_diagnostics_structure(self, client):
        resp = client.get("/api/diagnostics")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert data["total"] == 10
        assert "passed" in data
        assert "warnings" in data
        assert "failed" in data
        assert len(data["checks"]) == 10
        for chk in data["checks"]:
            assert "id" in chk
            assert "name" in chk
            assert chk["status"] in ["PASS", "WARN", "FAIL"]

    def test_audit_logs_retrieval(self, client):
        resp = client.get("/api/audit-logs")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "logs" in data
        assert isinstance(data["logs"], list)


class TestAGYTaskCenterAPIs:
    """Tests AGY status transparency and remote authentication enforcement."""

    def test_agy_status_reporting(self, client):
        resp = client.get("/api/agy/status")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["success"] is True
        assert "remote_api" in data
        assert "cli_detected" in data
        # If unauthenticated, status_code must reflect 401 or configured: False
        if not data["remote_api"]["configured"]:
            assert data["remote_api"]["status_code"] in [401, None]

    def test_agy_task_remote_unauthorized(self, client):
        # Attempting remote execution without token must return 401 Unauthorized
        resp = client.post("/api/agy/task", json={
            "task_name": "verify_all",
            "use_remote": True
        })
        assert resp.status_code == 401
        data = resp.get_json()
        assert data["success"] is False
        assert "401" in data["error"]


class TestSecurityKeysEndpoint:
    """Verifies that private keys can NEVER be accessed through API endpoints."""

    def test_public_key_endpoint_safety(self, client):
        resp = client.get("/api/keys/public")
        # Can be 200 or 404 depending on whether teacher_public_key.pem exists in config/keys
        if resp.status_code == 200:
            data = resp.get_json()
            assert "private" not in data.get("filename", "").lower()
            assert "BEGIN RSA PRIVATE KEY" not in data.get("content", "")
            assert "BEGIN PRIVATE KEY" not in data.get("content", "")
        else:
            assert resp.status_code == 404
