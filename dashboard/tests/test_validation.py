#!/usr/bin/env python3
"""
Unit tests for Host Validation, Security Sanitization, and Profile Engine.
"""

import sys
from pathlib import Path

# Add dashboard to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest
from modules.connectivity import validate_host
from modules.profiles import validate_profile_json, compute_diff


class TestHostValidation:
    """Tests host validation against injection attacks, illegal characters, and length limits."""

    def test_valid_hostnames(self):
        valid_hosts = [
            "slave-pc-01",
            "lab-workstation.local",
            "192.168.1.100",
            "10.0.0.1",
            "COMPUTER_123",
            "pc-test-42.school.internal"
        ]
        for host in valid_hosts:
            ok, res = validate_host(host)
            assert ok is True, f"Expected {host} to be valid, but got: {res}"
            assert res == host

    def test_reject_shell_metacharacters(self):
        dangerous_hosts = [
            "slave-01; rm -rf /",
            "host && calc.exe",
            "192.168.1.1 | whoami",
            "`id`",
            "$(whoami)",
            "host<script>",
            "host>out.txt",
            "slave' OR '1'='1",
            'slave" & dir',
            "host\nnewline",
            "host\rreturn"
        ]
        for host in dangerous_hosts:
            ok, msg = validate_host(host)
            assert ok is False, f"Expected injection attempt '{host}' to be rejected"
            assert "illegal metacharacters" in msg.lower() or "must contain only" in msg.lower()

    def test_reject_spaces_and_empty(self):
        invalid_inputs = [
            "",
            "   ",
            None,
            "slave 01",
            "192.168. 1.1"
        ]
        for host in invalid_inputs:
            ok, msg = validate_host(host)
            assert ok is False

    def test_reject_exceedingly_long_host(self):
        long_host = "a" * 256
        ok, msg = validate_host(long_host)
        assert ok is False
        assert "exceeds maximum length" in msg


class TestProfileValidation:
    """Tests JSON profile verification and structural integrity."""

    def test_valid_profile_json(self):
        valid_content = """{
            "Authentication": {
                "Method": 1
            },
            "Service": {
                "Autostart": "1"
            }
        }"""
        valid, parsed, msg = validate_profile_json(valid_content)
        assert valid is True
        assert isinstance(parsed, dict)
        assert parsed["Authentication"]["Method"] == 1

    def test_invalid_syntax_json(self):
        broken_json = """{
            "Authentication": {
                "Method": 1,
            }
        }"""
        valid, parsed, msg = validate_profile_json(broken_json)
        assert valid is False
        assert parsed is None
        assert "syntax error" in msg.lower()

    def test_non_dictionary_json(self):
        array_json = """["item1", "item2"]"""
        valid, parsed, msg = validate_profile_json(array_json)
        assert valid is False
        assert parsed is None
        assert "must be a json object" in msg.lower()

    def test_compute_diff(self):
        mod_content = '{\n  "CustomKey": "CustomValue"\n}'
        diff = compute_diff("master", mod_content)
        assert isinstance(diff, str)
        assert len(diff) > 0
        assert "CustomKey" in diff or "No changes detected" in diff
