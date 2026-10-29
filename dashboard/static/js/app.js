/* =========================================================
   VEYON OPS — Enterprise Cyber Administration Platform
   Modern Vanilla JavaScript Application Core
   ========================================================= */

document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initOverview();
    initMasterSetup();
    initSlaveManagement();
    initProfileEditor();
    initAgyTaskCenter();
    initDiagnostics();
    initLogs();

    // Start live sidebar clock
    initLiveClock();

    // Initial system load
    refreshSystemStatus();

    // Auto-refresh status every 15 seconds
    setInterval(refreshSystemStatus, 15000);
});

// =========================================================
// 1. NAVIGATION & ROUTING
// =========================================================

function initNavigation() {
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const tabId = link.getAttribute('data-tab');
            navigateToTab(tabId);
        });
    });

    const refreshBtn = document.getElementById('btn-refresh-all');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', async () => {
            refreshBtn.classList.add('refreshing');
            await refreshSystemStatus();
            setTimeout(() => refreshBtn.classList.remove('refreshing'), 600);
            showNotification('Dashboard telemetry refreshed.', 'info');
        });
    }
}

function navigateToTab(tabId) {
    document.querySelectorAll('.nav-link').forEach(link => {
        if (link.getAttribute('data-tab') === tabId) {
            link.classList.add('active');
        } else {
            link.classList.remove('active');
        }
    });

    document.querySelectorAll('.tab-pane').forEach(pane => {
        pane.classList.remove('active');
    });

    const activePane = document.getElementById(`tab-${tabId}`);
    if (activePane) {
        activePane.classList.add('active');
    }

    const titles = {
        overview: 'Overview',
        master: 'Master PC Configuration',
        slaves: 'Slave Management & Network Fleet',
        profiles: 'Configuration Profiles & JSON Editor',
        agy: 'Antigravity (AGY) Task Center',
        diagnostics: 'System Diagnostics & Health Check',
        logs: 'Operations & Security Audit Logs'
    };
    const titleEl = document.getElementById('current-page-title');
    if (titleEl) titleEl.textContent = titles[tabId] || 'Dashboard';

    if (tabId === 'slaves') loadSlavesTable();
    if (tabId === 'profiles') loadSelectedProfile();
    if (tabId === 'agy') loadAgyStatus();
    if (tabId === 'diagnostics') loadDiagnostics();
    if (tabId === 'logs') loadAuditLogs();
}

function initLiveClock() {
    const clockEl = document.getElementById('sidebar-clock-time');
    if (!clockEl) return;
    const updateTime = () => {
        const d = new Date();
        clockEl.textContent = d.toTimeString().split(' ')[0];
    };
    updateTime();
    setInterval(updateTime, 1000);
}

// =========================================================
// 2. SYSTEM STATUS & OVERVIEW
// =========================================================

async function refreshSystemStatus() {
    try {
        const res = await fetch('/api/system/status');
        const data = await res.json();
        if (!data.success) return;

        // Privilege Chip
        const privBadge = document.getElementById('privilege-badge');
        if (privBadge) {
            if (data.is_admin) {
                privBadge.className = 'privilege-chip elevated';
                privBadge.innerHTML = `
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path></svg>
                    <span>Administrator (Full Access)</span>
                `;
                privBadge.title = 'Running with elevated Windows Administrator token.';
            } else {
                privBadge.className = 'privilege-chip standard';
                privBadge.innerHTML = `
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path></svg>
                    <span>Standard User (UAC Restricted)</span>
                `;
                privBadge.title = 'Run PowerShell as Administrator to configure services, firewall rules, and HKLM registry.';
            }
        }

        // User Avatar & Chips
        const username = data.username || 'USER';
        const userBadge = document.getElementById('system-user-badge');
        if (userBadge) userBadge.textContent = username;

        const hostBadge = document.getElementById('system-hostname');
        if (hostBadge) hostBadge.textContent = data.hostname || 'LOCAL';

        const initials = username.split(' ').map(p => p[0]).filter(Boolean).join('').substring(0, 2).toUpperCase() || 'OP';
        const avatarEl = document.getElementById('user-avatar-initials');
        if (avatarEl) avatarEl.textContent = initials;

        // Overall Status Header Pill
        const overallStatus = document.getElementById('system-overall-status');
        if (overallStatus) {
            if (data.service?.status === 'Running' && data.port_11100_listening) {
                overallStatus.textContent = 'All Systems Operational';
            } else if (data.service?.status !== 'Running') {
                overallStatus.textContent = 'VeyonService Stopped';
            } else {
                overallStatus.textContent = 'Port 11100 Inactive';
            }
        }

        // Overview Cards: Role
        const masterCard = document.getElementById('card-master-status');
        const masterKeys = document.getElementById('card-master-keys');
        const roleChip = document.getElementById('card-role-chip');
        if (masterCard) {
            masterCard.textContent = data.role_detected;
            if (data.role_detected === 'Master') {
                masterCard.style.color = '#ffffff';
                if (roleChip) {
                    roleChip.className = 'stat-status-chip cyan';
                    roleChip.textContent = 'CONTROLLER';
                }
            } else if (data.role_detected === 'Slave') {
                masterCard.style.color = 'var(--accent-cyan)';
                if (roleChip) {
                    roleChip.className = 'stat-status-chip success';
                    roleChip.textContent = 'STUDENT CLIENT';
                }
            } else {
                masterCard.style.color = 'var(--accent-amber)';
                if (roleChip) {
                    roleChip.className = 'stat-status-chip warning';
                    roleChip.textContent = 'UNCONFIGURED';
                }
            }
        }
        if (masterKeys) {
            masterKeys.innerHTML = `
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>
                <span>Keys: ${data.installed_keys.join(', ') || 'None installed'}</span>
            `;
        }

        // Slaves Count Card
        const totalSlaves = data.slave_count || 0;
        const connSlaves = data.connected_slaves || 0;
        const slaveCountEl = document.getElementById('card-slave-count');
        const slaveSubEl = document.getElementById('card-slave-sub');
        const reachChip = document.getElementById('card-reach-chip');
        if (slaveCountEl) slaveCountEl.textContent = `${connSlaves} / ${totalSlaves}`;
        if (slaveSubEl) {
            slaveSubEl.innerHTML = `
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><polyline points="20 6 9 17 4 12"></polyline></svg>
                <span>${connSlaves} verified online via TCP 11100</span>
            `;
        }
        if (reachChip) {
            if (totalSlaves > 0 && connSlaves === totalSlaves) {
                reachChip.className = 'stat-status-chip success';
                reachChip.textContent = '100% REACHABLE';
            } else if (connSlaves > 0) {
                reachChip.className = 'stat-status-chip cyan';
                reachChip.textContent = `${Math.round((connSlaves / totalSlaves) * 100)}% REACHABLE`;
            } else {
                reachChip.className = 'stat-status-chip warning';
                reachChip.textContent = totalSlaves > 0 ? 'OFFLINE' : 'NO CLIENTS';
            }
        }
        const sidebarSlaveBadge = document.getElementById('sidebar-slave-badge');
        if (sidebarSlaveBadge) {
            sidebarSlaveBadge.textContent = `${connSlaves} Online`;
        }

        // Service Status Card
        const svcCard = document.getElementById('card-service-status');
        const svcStatus = data.service?.status || 'Unknown';
        const svcChip = document.getElementById('card-service-chip');
        if (svcCard) {
            svcCard.textContent = svcStatus;
            svcCard.style.color = (svcStatus === 'Running') ? 'var(--accent-emerald-light)' : 'var(--accent-rose)';
        }
        if (svcChip) {
            if (svcStatus === 'Running') {
                svcChip.className = 'stat-status-chip success';
                svcChip.textContent = 'ACTIVE';
            } else {
                svcChip.className = 'stat-status-chip warning';
                svcChip.textContent = 'STOPPED';
            }
        }

        // Port & Server Card
        const portCard = document.getElementById('card-port-status');
        const portChip = document.getElementById('card-port-chip');
        const serverProc = document.getElementById('card-server-proc');
        if (portCard) {
            if (data.port_11100_listening) {
                portCard.textContent = '11100 ACTIVE';
                portCard.style.color = 'var(--accent-emerald-light)';
                if (portChip) {
                    portChip.className = 'stat-status-chip success';
                    portChip.textContent = 'LISTENING';
                }
            } else {
                portCard.textContent = 'PORT CLOSED';
                portCard.style.color = 'var(--accent-amber)';
                if (portChip) {
                    portChip.className = 'stat-status-chip warning';
                    portChip.textContent = 'INACTIVE';
                }
            }
        }
        if (serverProc) {
            serverProc.innerHTML = `
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"></polyline></svg>
                <span>Server Process: ${data.server_process_running ? 'Running' : 'Service Managed'}</span>
            `;
        }

        // Environment Matrix Tiles
        const envVeyon = document.getElementById('env-veyon-version');
        if (envVeyon) envVeyon.textContent = data.veyon_version ? `${data.veyon_version} (64-bit)` : 'Not Detected';

        const envCli = document.getElementById('env-cli-path');
        if (envCli) envCli.textContent = data.veyon_cli_path || 'Not detected in PATH';

        const primaryIp = data.network_interfaces?.[0]?.ip || '127.0.0.1';
        const envIp = document.getElementById('env-ip-address');
        if (envIp) envIp.textContent = primaryIp;

        const envUser = document.getElementById('env-user-priv');
        if (envUser) envUser.textContent = `${data.username} (${data.privilege_level})`;

        const osTag = document.getElementById('overview-os-tag');
        if (osTag) osTag.textContent = data.os_platform || 'Windows';

        // Sidebar Role Text
        const sidebarRole = document.getElementById('sidebar-role-text');
        if (sidebarRole) sidebarRole.textContent = `${data.role_detected} Host`;

    } catch (err) {
        console.error('Failed refreshing system status:', err);
    }

    loadRecentLogs();
}

function initOverview() {
    document.getElementById('btn-quick-master')?.addEventListener('click', () => {
        navigateToTab('master');
    });

    document.getElementById('btn-quick-verify')?.addEventListener('click', () => {
        navigateToTab('master');
        runVerification('Auto');
    });

    document.getElementById('btn-quick-restart-svc')?.addEventListener('click', () => {
        confirmAction(
            'Restart Veyon Windows Service',
            'Are you sure you want to restart VeyonService? Active Veyon sessions will momentarily reconnect.',
            'Requires Administrator privileges.',
            async () => {
                const btn = document.getElementById('btn-quick-restart-svc');
                if (btn) {
                    btn.disabled = true;
                    btn.innerHTML = '<span class="spinner-icon"></span> <span>Restarting...</span>';
                }
                try {
                    const res = await fetch('/api/service/restart', { method: 'POST', headers: { 'Content-Type': 'application/json' } });
                    const d = await res.json();
                    if (d.success) {
                        showNotification('Veyon Service restarted successfully.', 'success');
                    } else {
                        showNotification(`Restart failed: ${d.error || d.stderr}`, 'error');
                    }
                } catch (e) {
                    showNotification(`Error: ${e}`, 'error');
                } finally {
                    if (btn) {
                        btn.disabled = false;
                        btn.innerHTML = `
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><polyline points="1 4 1 10 7 10"></polyline><polyline points="23 20 23 14 17 14"></polyline><path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"></path></svg>
                            <span>Restart Veyon Service</span>
                        `;
                    }
                    refreshSystemStatus();
                }
            }
        );
    });

    document.getElementById('btn-quick-download-pubkey')?.addEventListener('click', () => {
        window.location.href = '/api/keys/public?download=true';
        showNotification('Downloading teacher_public_key.pem...', 'info');
    });
}

async function loadRecentLogs() {
    try {
        // Exclude repetitive auto-poll pings so the overview table shows meaningful operations
        const res = await fetch('/api/audit-logs?exclude_ops=CLIENT_CONNECTIVITY_SCAN&limit=6');
        const data = await res.json();
        const tbody = document.getElementById('overview-recent-logs');
        if (!tbody) return;

        if (!data.success || !data.logs.length) {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 24px;">No recent operational events recorded yet.</td></tr>';
            return;
        }

        tbody.innerHTML = data.logs.map(l => {
            const timeParts = l.timestamp.split(' ');
            const timeFormatted = timeParts[1] || l.timestamp;
            const dateFormatted = timeParts[0] || '';
            const outcomeBadge = l.outcome === 'SUCCESS' ? 'success' : (l.outcome === 'WARNING' ? 'warning' : 'danger');

            return `
            <tr>
                <td>
                    <div style="font-family: var(--font-mono); font-size: 12.5px; font-weight: 600; color: #ffffff;">${timeFormatted}</div>
                    <div style="font-size: 11px; color: var(--text-muted);">${dateFormatted}</div>
                </td>
                <td><span class="badge-pill ${getBadgeClass(l.level)}">${l.level}</span></td>
                <td><span class="badge-pill ${outcomeBadge}">${l.outcome}</span></td>
                <td><strong style="color: #ffffff; font-size: 13px;">${escapeHtml(l.operation)}</strong></td>
                <td style="color: var(--text-secondary); font-size: 12.5px; max-width: 320px; line-height: 1.4;">${escapeHtml(l.details || '')}</td>
            </tr>
            `;
        }).join('');
    } catch (e) {
        console.error('Failed loading recent logs:', e);
    }
}

// =========================================================
// 3. MASTER SETUP & TERMINAL CONSOLE
// =========================================================

function initMasterSetup() {
    const form = document.getElementById('form-master-setup');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const keyName = document.getElementById('m-key-name').value.trim() || 'teacher';
        const roomName = document.getElementById('m-room-name').value.trim();
        const clientHostsRaw = document.getElementById('m-client-hosts').value.trim();
        const force = document.getElementById('m-force').checked;

        const clientHosts = clientHostsRaw ? clientHostsRaw.split(',').map(s => s.trim()).filter(Boolean) : [];

        const btn = document.getElementById('btn-run-master-setup');
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-icon"></span> <span>Configuring Master...</span>';

        writeTerminal('master-terminal', `[INFO] Initializing Master configuration pipeline...\n[INFO] Key Name: ${keyName}\n[INFO] Classroom: ${roomName || 'Default Classroom'}\n[INFO] Target Hosts: ${clientHosts.join(', ') || 'None specified'}\n\n`);

        try {
            const res = await fetch('/api/master/configure', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    key_name: keyName,
                    room_name: roomName,
                    client_hosts: clientHosts,
                    force: force
                })
            });

            const data = await res.json();
            if (data.stdout) {
                appendTerminalFormatted('master-terminal', data.stdout);
            }
            if (data.stderr) {
                appendTerminalFormatted('master-terminal', `\n[ERROR] ${data.stderr}\n`);
            }

            if (data.success) {
                appendTerminalFormatted('master-terminal', `\n[PASS] Master Configuration applied successfully in ${data.execution_time_sec}s.\n`);
                showNotification('Master Auto-Configuration finished successfully!', 'success');
            } else {
                appendTerminalFormatted('master-terminal', `\n[FAIL] Script exited with code ${data.exit_code}.\n`);
                showNotification('Master configuration completed with errors. Check console.', 'error');
            }
        } catch (err) {
            appendTerminalFormatted('master-terminal', `\n[ERROR] Request failed: ${err}\n`);
        } finally {
            btn.disabled = false;
            btn.innerHTML = `
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                <span>Run Master Auto-Configuration</span>
            `;
            refreshSystemStatus();
        }
    });

    document.getElementById('btn-preview-master')?.addEventListener('click', async () => {
        const keyName = document.getElementById('m-key-name').value.trim() || 'teacher';
        const roomName = document.getElementById('m-room-name').value.trim();
        const clientHostsRaw = document.getElementById('m-client-hosts').value.trim();
        const clientHosts = clientHostsRaw ? clientHostsRaw.split(',').map(s => s.trim()).filter(Boolean) : [];

        try {
            const res = await fetch('/api/master/preview', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key_name: keyName, room_name: roomName, client_hosts: clientHosts })
            });
            const d = await res.json();
            if (d.success) {
                document.getElementById('preview-master-content').innerHTML = `
<div style="color: var(--accent-cyan); margin-bottom: 12px; font-weight: 700;">[PROPOSED CONFIGURATION SPECIFICATION]</div>
<div><strong>Key Pair:</strong> ${escapeHtml(d.preview.key_pair.name)}</div>
<div style="margin-left: 12px; color: var(--text-muted);">&bull; Private: ${escapeHtml(d.preview.key_pair.private_key)}</div>
<div style="margin-left: 12px; color: var(--text-muted);">&bull; Public: ${escapeHtml(d.preview.key_pair.public_key)}</div>
<div style="margin-top: 10px;"><strong>Classroom:</strong> ${escapeHtml(d.preview.classroom.name)}</div>
<div style="margin-left: 12px; color: var(--text-muted);">&bull; Clients to register: ${d.preview.classroom.clients_to_register.length ? escapeHtml(d.preview.classroom.clients_to_register.join(', ')) : 'None'}</div>
<div style="margin-top: 10px;"><strong>Enforced Policies:</strong></div>
<pre style="background: rgba(0,0,0,0.4); padding: 10px; border-radius: 6px; margin-top: 6px; color: var(--accent-emerald-light);">${JSON.stringify(d.preview.settings_to_enforce, null, 2)}</pre>
<div style="margin-top: 10px;"><strong>Service Action:</strong> ${escapeHtml(d.preview.service_action)}</div>
`;
                showModal('modal-preview-master');
            } else {
                showNotification(`Preview error: ${d.error}`, 'error');
            }
        } catch (e) {
            showNotification(`Preview failed: ${e}`, 'error');
        }
    });

    document.getElementById('btn-validate-master')?.addEventListener('click', () => {
        const keyName = document.getElementById('m-key-name').value.trim() || 'teacher';
        runVerification(keyName);
    });

    document.getElementById('btn-clear-terminal')?.addEventListener('click', () => {
        writeTerminal('master-terminal', 'Console cleared.\n');
    });
}

async function runVerification(keyName) {
    writeTerminal('master-terminal', `[INFO] Invoking Validate-Master.ps1 (Key: ${keyName})...\n\n`);
    try {
        const res = await fetch('/api/master/validate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key_name: keyName })
        });
        const data = await res.json();
        if (data.stdout) {
            appendTerminalFormatted('master-terminal', data.stdout);
        }
        if (data.stderr) {
            appendTerminalFormatted('master-terminal', `\n[ERROR] ${data.stderr}\n`);
        }
        if (data.success) {
            showNotification(`Master health validation passed!`, 'success');
        } else {
            showNotification(`Validation reported warnings or issues.`, 'warn');
        }
    } catch (err) {
        appendTerminalFormatted('master-terminal', `\n[ERROR] Validation call failed: ${err}\n`);
    }
}

function writeTerminal(id, text) {
    const term = document.getElementById(id);
    if (!term) return;
    term.textContent = text;
    term.scrollTop = term.scrollHeight;
}

function appendTerminalFormatted(id, text) {
    const term = document.getElementById(id);
    if (!term) return;
    let escaped = escapeHtml(text);

    escaped = escaped
        .replace(/\[PASS\]/g, '<span class="t-pass">[PASS]</span>')
        .replace(/\[OK\]/g, '<span class="t-pass">[OK]</span>')
        .replace(/\[SUCCESS\]/g, '<span class="t-pass">[SUCCESS]</span>')
        .replace(/\[FAIL\]/g, '<span class="t-fail">[FAIL]</span>')
        .replace(/\[ERROR\]/g, '<span class="t-fail">[ERROR]</span>')
        .replace(/\[WARN\]/g, '<span class="t-warn">[WARN]</span>')
        .replace(/\[WARNING\]/g, '<span class="t-warn">[WARNING]</span>')
        .replace(/\[INFO\]/g, '<span class="t-info">[INFO]</span>')
        .replace(/&gt;&gt;&gt;/g, '<span class="t-info">&gt;&gt;&gt;</span>');

    term.innerHTML += escaped;
    term.scrollTop = term.scrollHeight;
}

// =========================================================
// 4. SLAVE MANAGEMENT
// =========================================================

function initSlaveManagement() {
    document.getElementById('btn-open-add-slave')?.addEventListener('click', () => {
        showModal('modal-add-slave');
    });

    document.getElementById('form-add-computer')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const name = document.getElementById('new-comp-name').value.trim();
        const host = document.getElementById('new-comp-host').value.trim();
        const room = document.getElementById('new-comp-room').value.trim();

        try {
            const res = await fetch('/api/clients', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: name, host: host, room_name: room })
            });
            const d = await res.json();
            if (d.success) {
                closeModal('modal-add-slave');
                showNotification(`Registered client workstation '${name}' successfully.`, 'success');
                loadSlavesTable();
                refreshSystemStatus();
            } else {
                showNotification(`Error: ${d.error}`, 'error');
            }
        } catch (err) {
            showNotification(`Error: ${err}`, 'error');
        }
    });

    document.getElementById('btn-test-all-slaves')?.addEventListener('click', testAllSlavesConnectivity);

    document.getElementById('btn-copy-slave-cmd')?.addEventListener('click', () => {
        const cmd = document.getElementById('slave-command-box').textContent.trim();
        navigator.clipboard.writeText(cmd).then(() => {
            showNotification('Slave setup command copied to clipboard!', 'info');
        });
    });

    document.getElementById('btn-check-winrm')?.addEventListener('click', async () => {
        const host = document.getElementById('remote-target-host').value.trim();
        const statusEl = document.getElementById('winrm-test-status');
        if (!host) {
            statusEl.textContent = 'Please enter a target host.';
            return;
        }

        statusEl.innerHTML = '<span class="spinner-icon"></span> Testing WinRM transport...';
        try {
            const res = await fetch('/api/clients/remote-deploy', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ host: host })
            });
            const d = await res.json();
            if (d.transport_available) {
                statusEl.innerHTML = `<span style="color: var(--accent-emerald-light); font-weight: 600;">&#10004; WinRM transport reachable on ${escapeHtml(host)}.</span>`;
            } else {
                statusEl.innerHTML = `<span style="color: var(--accent-rose); font-weight: 600;">&#10006; ${escapeHtml(d.error || 'WinRM unreachable')}</span><br><span style="color: var(--text-muted); font-size: 11px;">${escapeHtml(d.remediation || '')}</span>`;
            }
        } catch (e) {
            statusEl.textContent = `Error: ${e}`;
        }
    });
}

function getClientStateBadge(status) {
    if (status === 'CONNECTED') return 'success';
    if (status === 'PORT_OPEN_PING_BLOCKED' || status === 'PING_REPLIED_PORT_CLOSED') return 'warning';
    if (status === 'DISCONNECTED' || status === 'CHECK FAILED') return 'danger';
    return 'info';
}

async function loadSlavesTable() {
    const tbody = document.getElementById('slaves-table-body');
    if (!tbody) return;
    tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 24px;">Loading registered workstations...</td></tr>';

    try {
        const res = await fetch('/api/clients');
        const data = await res.json();
        if (!data.success || !data.clients.length) {
            tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 24px;">No client computers registered yet. Click "+ Register Student PC" above.</td></tr>';
            return;
        }

        tbody.innerHTML = data.clients.map(c => `
            <tr id="row-client-${escapeHtml(c.id)}">
                <td><strong style="color: #ffffff; font-size: 13.5px;">${escapeHtml(c.name)}</strong></td>
                <td class="mono" style="color: var(--accent-cyan);">${escapeHtml(c.host)}</td>
                <td><span style="color: var(--text-secondary);">${escapeHtml(c.room_name || 'Default Classroom')}</span></td>
                <td><span class="badge-pill ${getClientStateBadge(c.status)}">${c.status}</span></td>
                <td id="ping-${escapeHtml(c.id)}">${c.ping_ms >= 0 ? `<span class="badge-pill success">${c.ping_ms} ms</span>` : '<span class="badge-pill info">Untested</span>'}</td>
                <td id="port-${escapeHtml(c.id)}">${c.port_open ? '<span class="badge-pill success">TCP 11100 Open</span>' : '<span class="badge-pill info">Untested</span>'}</td>
                <td style="font-size: 11px; color: var(--text-muted);">${c.last_check_timestamp ? c.last_check_timestamp.substring(11, 19) : 'Never'}</td>
                <td style="text-align: right;">
                    <div style="display: inline-flex; gap: 8px;">
                        <button class="btn-modern btn-secondary btn-sm" onclick="testSingleClient('${escapeHtml(c.id)}', '${escapeHtml(c.host)}')">Probe</button>
                        <button class="btn-modern btn-danger btn-sm" onclick="removeClient('${escapeHtml(c.id)}')">Delete</button>
                    </div>
                </td>
            </tr>
        `).join('');

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="8" style="text-align: center; color: var(--accent-rose); padding: 20px;">Error loading clients: ${err}</td></tr>`;
    }
}

async function testSingleClient(id, host) {
    const pingEl = document.getElementById(`ping-${id}`);
    const portEl = document.getElementById(`port-${id}`);
    if (pingEl) pingEl.innerHTML = '<span class="spinner-icon"></span>';
    if (portEl) portEl.innerHTML = '<span class="spinner-icon"></span>';

    try {
        const res = await fetch('/api/clients/validate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ hosts: [host] })
        });
        const d = await res.json();
        if (d.success && d.results.length) {
            const r = d.results[0];
            loadSlavesTable();
            refreshSystemStatus();
            showNotification(`Client ${host} verified: ${r.state}`, r.state === 'CONNECTED' ? 'success' : 'warn');
        }
    } catch (e) {
        if (pingEl) pingEl.innerHTML = '<span class="badge-pill danger">Error</span>';
        if (portEl) portEl.innerHTML = '<span class="badge-pill danger">Error</span>';
    }
}

async function testAllSlavesConnectivity() {
    showNotification('Probing connectivity for all registered clients...', 'info');
    try {
        const res = await fetch('/api/clients/validate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ hosts: [] })
        });
        const d = await res.json();
        if (d.success) {
            loadSlavesTable();
            refreshSystemStatus();
            showNotification(`Completed probe scan for ${d.results.length} clients.`, 'success');
        }
    } catch (e) {
        showNotification(`Connectivity test failed: ${e}`, 'error');
    }
}

function removeClient(id) {
    confirmAction(
        'Delete Client Computer',
        'Are you sure you want to remove this client from the Veyon directory?',
        'The workstation can be re-registered at any time.',
        async () => {
            try {
                const res = await fetch(`/api/clients/${id}`, { method: 'DELETE' });
                const d = await res.json();
                if (d.success) {
                    showNotification('Client removed successfully.', 'info');
                    loadSlavesTable();
                    refreshSystemStatus();
                } else {
                    showNotification('Failed to remove client.', 'error');
                }
            } catch (e) {
                showNotification(`Error: ${e}`, 'error');
            }
        }
    );
}

// =========================================================
// 5. PROFILE & JSON EDITOR
// =========================================================

function initProfileEditor() {
    const sel = document.getElementById('profile-selector');
    if (!sel) return;

    sel.addEventListener('change', loadSelectedProfile);

    document.getElementById('btn-format-json')?.addEventListener('click', () => {
        const ed = document.getElementById('json-editor');
        try {
            const parsed = JSON.parse(ed.value);
            ed.value = JSON.stringify(parsed, null, 2);
            showNotification('JSON formatted successfully.', 'info');
        } catch (e) {
            showNotification(`JSON syntax error: ${e.message}`, 'error');
        }
    });

    document.getElementById('btn-diff-profile')?.addEventListener('click', async () => {
        const profile = sel.value;
        const content = document.getElementById('json-editor').value;

        try {
            const res = await fetch(`/api/profiles/${profile}/diff`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ content: content })
            });
            const d = await res.json();
            if (d.success) {
                document.getElementById('diff-content').textContent = d.diff || 'No changes detected.';
                showModal('modal-diff');
            }
        } catch (e) {
            showNotification(`Diff error: ${e}`, 'error');
        }
    });

    document.getElementById('btn-download-profile')?.addEventListener('click', () => {
        const profile = sel.value;
        window.location.href = `/api/profiles/${profile}/download`;
    });

    document.getElementById('btn-save-profile')?.addEventListener('click', () => {
        const profile = sel.value;
        confirmAction(
            `Save Changes to ${profile}.json`,
            `This will write the modified configuration to disk. A pre-save backup will be created automatically in config/backups/.`,
            null,
            async () => {
                const ed = document.getElementById('json-editor');
                let parsed;
                try {
                    parsed = JSON.parse(ed.value);
                } catch (e) {
                    showNotification(`Invalid JSON: ${e.message}`, 'error');
                    return;
                }

                try {
                    const res = await fetch(`/api/profiles/${profile}`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(parsed)
                    });
                    const d = await res.json();
                    if (d.success) {
                        showNotification(`Saved ${profile}.json with backup.`, 'success');
                        loadSelectedProfile();
                    } else {
                        showNotification(`Save failed: ${d.error}`, 'error');
                    }
                } catch (e) {
                    showNotification(`Save failed: ${e}`, 'error');
                }
            }
        );
    });

    document.getElementById('btn-apply-profile')?.addEventListener('click', () => {
        const profile = sel.value;
        confirmAction(
            `Apply ${profile}.json to Live Veyon System`,
            `This will import the configuration into the Windows registry (HKLM:\\Software\\Veyon Solutions\\Veyon) using veyon-cli.exe.`,
            'Requires Administrator privileges.',
            async () => {
                try {
                    const res = await fetch(`/api/profiles/${profile}/apply`, { method: 'POST' });
                    const d = await res.json();
                    if (d.success) {
                        showNotification(`Profile ${profile} applied to live Veyon system!`, 'success');
                        refreshSystemStatus();
                    } else {
                        showNotification(`Apply failed: ${d.error || d.stderr}`, 'error');
                    }
                } catch (e) {
                    showNotification(`Apply error: ${e}`, 'error');
                }
            }
        );
    });
}

async function loadSelectedProfile() {
    const sel = document.getElementById('profile-selector');
    const profile = sel.value;
    const ed = document.getElementById('json-editor');
    ed.value = 'Loading profile...';

    try {
        const res = await fetch(`/api/profiles/${profile}`);
        const data = await res.json();
        if (data.success) {
            ed.value = JSON.stringify(data.data, null, 2);
        } else {
            ed.value = `// Error: ${data.error}`;
        }
    } catch (e) {
        ed.value = `// Request failed: ${e}`;
    }

    loadBackupsList();
}

async function loadBackupsList() {
    try {
        const res = await fetch('/api/profiles');
        const data = await res.json();
        const tbody = document.getElementById('backups-table-body');
        if (!tbody) return;

        if (!data.success || !data.backups || !data.backups.length) {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 20px;">No configuration snapshots recorded yet.</td></tr>';
            return;
        }

        tbody.innerHTML = data.backups.map(b => `
            <tr>
                <td class="mono" style="font-size: 11px;">${b.timestamp}</td>
                <td><span class="badge-pill info">${escapeHtml(b.profile_name)}</span></td>
                <td class="mono" style="font-size: 11.5px; color: var(--accent-cyan);">${escapeHtml(b.filename)}</td>
                <td style="color: var(--text-secondary);">${b.size_bytes} bytes</td>
                <td style="text-align: right;">
                    <button class="btn-modern btn-secondary btn-sm" onclick="restoreBackup('${b.id}')">Restore</button>
                </td>
            </tr>
        `).join('');
    } catch (e) {}
}

function restoreBackup(id) {
    confirmAction(
        'Restore Configuration Snapshot',
        'Are you sure you want to restore this configuration snapshot? A safety backup will be created first.',
        'Requires Administrator privileges to apply to registry.',
        async () => {
            try {
                const res = await fetch(`/api/backups/${id}/restore`, { method: 'POST' });
                const d = await res.json();
                if (d.success) {
                    showNotification('Backup restored successfully!', 'success');
                    loadSelectedProfile();
                    refreshSystemStatus();
                } else {
                    showNotification(`Restore failed: ${d.error}`, 'error');
                }
            } catch (e) {
                showNotification(`Restore error: ${e}`, 'error');
            }
        }
    );
}

// =========================================================
// 6. AGY TASK CENTER
// =========================================================

function initAgyTaskCenter() {}

async function loadAgyStatus() {
    const badge = document.getElementById('agy-badge-status');
    const details = document.getElementById('agy-status-details');
    const warning = document.getElementById('agy-auth-warning');
    if (!badge || !details) return;

    try {
        const res = await fetch('/api/agy/status');
        const data = await res.json();
        if (!data.success) return;

        if (data.remote_api?.status_code === 401) {
            badge.className = 'badge-pill danger';
            badge.textContent = 'HTTP 401 Unauthorized';
            if (warning) {
                warning.style.display = 'block';
                warning.innerHTML = `<strong>Authentication Notice:</strong> AGY integration unavailable — use the supported local CLI or continue configuration independently. (HTTP 401 Unauthorized: Invalid or missing token)`;
            }
        } else if (!data.remote_api?.configured) {
            badge.className = 'badge-pill warning';
            badge.textContent = 'Standalone Mode';
            if (warning) warning.style.display = 'none';
        } else {
            badge.className = 'badge-pill success';
            badge.textContent = 'Connected';
            if (warning) warning.style.display = 'none';
        }

        details.innerHTML = `
            <div><strong>Antigravity CLI:</strong> ${data.cli_detected ? `<span style="color: var(--accent-emerald-light); font-weight: 600;">${data.cli_path}</span>` : '<span style="color: var(--accent-amber);">Not found in PATH</span>'}</div>
            <div style="margin-top: 4px;"><strong>Daemon Status:</strong> ${escapeHtml(data.daemon_status || 'Not registered')}</div>
            <div style="margin-top: 4px;"><strong>Project Path:</strong> <span class="mono">${escapeHtml(data.project_path || '')}</span></div>
            <div style="margin-top: 4px;"><strong>Integration Engine:</strong> <span style="color: var(--accent-cyan); font-weight: 600;">Local PowerShell Automation Engine (Approved Whitelist)</span></div>
            <div style="margin-top: 8px; font-size: 12px; color: var(--text-muted);">${escapeHtml(data.remote_api?.message || '')}</div>
        `;
    } catch (err) {
        badge.className = 'badge-pill danger';
        badge.textContent = 'Error';
    }
}

async function runAgyTask(taskName) {
    writeTerminal('agy-terminal', `[INFO] Requesting task execution: '${taskName}'...\n\n`);
    try {
        const res = await fetch('/api/agy/task', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ task_name: taskName })
        });
        const data = await res.json();

        if (res.status === 401) {
            appendTerminalFormatted('agy-terminal', `[FAIL] ${data.error || 'HTTP 401 Unauthorized'}\n[WARN] ${data.hint || ''}\n`);
            showNotification('AGY Authentication Required (HTTP 401)', 'error');
            return;
        }

        if (data.result?.stdout) {
            appendTerminalFormatted('agy-terminal', data.result.stdout);
        }
        if (data.result?.stderr) {
            appendTerminalFormatted('agy-terminal', `\n[ERROR] ${data.result.stderr}\n`);
        }

        if (data.success) {
            appendTerminalFormatted('agy-terminal', `\n[PASS] Task '${data.title}' completed successfully.\n`);
            showNotification(`Task '${data.title}' completed!`, 'success');
        } else {
            appendTerminalFormatted('agy-terminal', `\n[WARN] Task completed with warnings or error.\n`);
            showNotification(`Task '${data.title}' finished with warnings.`, 'warn');
        }
    } catch (e) {
        appendTerminalFormatted('agy-terminal', `\n[ERROR] Task dispatch error: ${e}\n`);
    }
}

// =========================================================
// 7. DIAGNOSTICS
// =========================================================

function initDiagnostics() {
    document.getElementById('btn-run-diagnostics')?.addEventListener('click', loadDiagnostics);
}

async function loadDiagnostics() {
    const tbody = document.getElementById('diagnostics-table-body');
    if (!tbody) return;
    tbody.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-muted); padding: 24px;"><span class="spinner-icon"></span> Running 10-point diagnostic inspection...</td></tr>';

    try {
        const res = await fetch('/api/diagnostics');
        const data = await res.json();
        if (!data.success) return;

        tbody.innerHTML = data.checks.map(c => {
            const badgeClass = c.status === 'PASS' ? 'success' : (c.status === 'WARN' ? 'warning' : 'danger');
            return `
            <tr>
                <td><strong style="color: #ffffff; font-size: 13.5px;">${c.id}. ${escapeHtml(c.name)}</strong></td>
                <td><span class="badge-pill ${badgeClass}">${c.status}</span></td>
                <td style="color: var(--text-secondary);">${escapeHtml(c.details)}</td>
                <td style="color: var(--text-muted); font-size: 12px;">${c.remediation ? escapeHtml(c.remediation) : '<span style="color: var(--accent-emerald-light); font-weight: 600;">&#10004; Verified Healthy</span>'}</td>
            </tr>
            `;
        }).join('');

        const diagBadge = document.getElementById('sidebar-diag-badge');
        if (diagBadge) {
            diagBadge.textContent = `${data.passed}/${data.total}`;
        }

        showNotification(`Diagnostics complete: ${data.passed}/${data.total} checks passed.`, data.failed === 0 ? 'success' : 'warn');

    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="4" style="text-align: center; color: var(--accent-rose); padding: 20px;">Failed running diagnostics: ${err}</td></tr>`;
    }
}

// =========================================================
// 8. AUDIT LOGS
// =========================================================

function initLogs() {
    document.getElementById('btn-refresh-logs')?.addEventListener('click', loadAuditLogs);

    document.getElementById('log-filter-level')?.addEventListener('change', loadAuditLogs);

    document.getElementById('log-search-input')?.addEventListener('input', debounce(loadAuditLogs, 350));

    document.getElementById('btn-export-logs')?.addEventListener('click', () => {
        window.location.href = '/api/audit-logs/export';
    });

    document.getElementById('btn-clear-logs')?.addEventListener('click', () => {
        confirmAction(
            'Clear Audit Logs',
            'Are you sure you want to purge all historical audit logs? This cannot be undone.',
            'Action will be recorded as a new audit event.',
            async () => {
                try {
                    const res = await fetch('/api/audit-logs', { method: 'DELETE' });
                    const d = await res.json();
                    if (d.success) {
                        showNotification('Audit logs cleared.', 'info');
                        loadAuditLogs();
                    }
                } catch (e) {
                    showNotification(`Error: ${e}`, 'error');
                }
            }
        );
    });
}

async function loadAuditLogs() {
    const level = document.getElementById('log-filter-level')?.value || 'ALL';
    const search = document.getElementById('log-search-input')?.value.trim() || '';
    const tbody = document.getElementById('full-logs-body');
    if (!tbody) return;

    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 24px;">Loading logs...</td></tr>';

    try {
        let url = `/api/audit-logs?level=${encodeURIComponent(level)}`;
        if (search) url += `&search=${encodeURIComponent(search)}`;

        const res = await fetch(url);
        const data = await res.json();
        if (!data.success || !data.logs.length) {
            tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 24px;">No log entries matching criteria.</td></tr>';
            return;
        }

        tbody.innerHTML = data.logs.map(l => {
            const outcomeBadge = l.outcome === 'SUCCESS' ? 'success' : (l.outcome === 'WARNING' ? 'warning' : 'danger');
            return `
            <tr>
                <td class="mono" style="font-size: 11.5px; color: var(--text-muted);">${l.timestamp}</td>
                <td><span class="badge-pill ${getBadgeClass(l.level)}">${l.level}</span></td>
                <td><span class="badge-pill ${outcomeBadge}">${l.outcome}</span></td>
                <td><strong style="color: #ffffff;">${escapeHtml(l.operation)}</strong></td>
                <td style="color: var(--text-secondary); font-size: 12.5px;">${escapeHtml(l.details || '')}</td>
                <td class="mono" style="font-size: 11.5px; color: var(--accent-cyan);">${escapeHtml(l.user || 'SYSTEM')}</td>
            </tr>
            `;
        }).join('');
    } catch (e) {
        tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; color: var(--accent-rose); padding: 20px;">Error loading logs: ${e}</td></tr>`;
    }
}

// =========================================================
// UTILITIES & MODAL HELPERS
// =========================================================

function showModal(id) {
    const m = document.getElementById(id);
    if (m) {
        m.classList.add('active');
        m.classList.add('show');
    }
}

function closeModal(id) {
    const m = document.getElementById(id);
    if (m) {
        m.classList.remove('active');
        m.classList.remove('show');
    }
}

let pendingAction = null;
function confirmAction(title, message, warning, onConfirm) {
    document.getElementById('confirm-modal-title').textContent = title;
    document.getElementById('confirm-modal-message').textContent = message;
    document.getElementById('confirm-modal-warning').textContent = warning || '';
    pendingAction = onConfirm;

    const btn = document.getElementById('confirm-modal-btn');
    btn.onclick = () => {
        closeModal('modal-confirm');
        if (pendingAction) {
            pendingAction();
            pendingAction = null;
        }
    };

    showModal('modal-confirm');
}

function showNotification(msg, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast-message ${type}`;
    toast.innerHTML = `<span>${escapeHtml(msg)}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(12px)';
        toast.style.transition = 'all 0.25s cubic-bezier(0.16, 1, 0.3, 1)';
        setTimeout(() => toast.remove(), 250);
    }, 3500);
}

window.copyText = function(elementId) {
    const el = document.getElementById(elementId);
    if (!el) return;
    const text = el.textContent || el.value;
    navigator.clipboard.writeText(text).then(() => {
        showNotification(`Copied to clipboard: ${text}`, 'info');
    }).catch(() => {
        showNotification('Copied to clipboard', 'info');
    });
};

function getBadgeClass(level) {
    switch (level.toUpperCase()) {
        case 'INFO': return 'info';
        case 'EXEC': return 'success';
        case 'WARN': return 'warning';
        case 'ERROR': return 'danger';
        default: return 'info';
    }
}

function escapeHtml(text) {
    if (!text) return '';
    return String(text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}
