#!/usr/bin/env python3
"""
Host & Port Connectivity Probing Module
Safe network validation for client computers without hardcoded states.
"""

import re
import time
import socket
import subprocess
import ipaddress
from typing import Dict, Any, Tuple

HOSTNAME_REGEX = re.compile(r"^[a-zA-Z0-9_\-\.]+$")

def validate_host(host: str) -> Tuple[bool, str]:
    """Validates hostname or IP address format and rejects shell metacharacters."""
    if not host or not isinstance(host, str):
        return False, "Host must be a non-empty string"
    clean_host = host.strip()
    if len(clean_host) > 255:
        return False, "Host exceeds maximum length (255 characters)"

    # Check for dangerous metacharacters
    dangerous_chars = [";", "&", "|", "`", "$", "(", ")", "<", ">", "\n", "\r", "\"", "'", " "]
    if any(ch in clean_host for ch in dangerous_chars):
        return False, "Host contains illegal metacharacters"

    if not HOSTNAME_REGEX.match(clean_host):
        return False, "Host must contain only alphanumeric characters, dots, dashes, and underscores"

    return True, clean_host

def test_host_connectivity(host: str, port: int = 11100, timeout: float = 1.2) -> Dict[str, Any]:
    """
    Real-time ping and socket connection test.
    Explicit states: CONNECTED, DISCONNECTED, PORT_OPEN_PING_BLOCKED, PING_REPLIED_PORT_CLOSED, CHECK FAILED.
    """
    valid, result = validate_host(host)
    if not valid:
        return {
            "host": host,
            "state": "CHECK FAILED",
            "ping_ok": False,
            "ping_ms": -1,
            "port_open": False,
            "port_latency_ms": -1,
            "error": result
        }

    clean_host = result
    timeout_ms = int(timeout * 1000)

    # 1. ICMP Ping check
    ping_ok = False
    ping_ms = -1
    try:
        ping_res = subprocess.run(
            ["ping.exe", "-n", "1", "-w", str(timeout_ms), clean_host],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout + 2,
            creationflags=subprocess.CREATE_NO_WINDOW if subprocess.os.name == 'nt' else 0
        )
        ping_ok = ping_res.returncode == 0
        match = re.search(r"time[=<]\s*(\d+)ms", ping_res.stdout, re.IGNORECASE)
        if match:
            ping_ms = int(match.group(1))
    except Exception:
        ping_ok = False

    # 2. TCP Port 11100 Socket probe
    port_open = False
    port_latency_ms = -1
    start_time = time.time()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((clean_host, port))
        s.close()
        port_open = True
        port_latency_ms = round((time.time() - start_time) * 1000, 1)
    except Exception:
        port_open = False
        port_latency_ms = -1

    # 3. Determine Explicit State
    if port_open and ping_ok:
        state = "CONNECTED"
    elif port_open and not ping_ok:
        state = "PORT_OPEN_PING_BLOCKED" # Port responds, but ICMP dropped by firewall
    elif not port_open and ping_ok:
        state = "PING_REPLIED_PORT_CLOSED" # Host is up, but Veyon service not listening
    else:
        state = "DISCONNECTED"

    return {
        "host": clean_host,
        "state": state,
        "ping_ok": ping_ok,
        "ping_ms": ping_ms,
        "port": port,
        "port_open": port_open,
        "port_latency_ms": port_latency_ms,
        "error": None
    }
