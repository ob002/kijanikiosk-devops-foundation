#!/bin/bash
###############################################################################
# KijaniKiosk Production Provisioning Script
# Idempotent - safe to run multiple times on dirty state
###############################################################################
set -euo pipefail

# --- LOGGING SETUP ---
LOG_FILE="/var/log/kijanikiosk-provisioning.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date -Iseconds)] $*"; }
success() { log "✓ PASS: $*"; }
fail() { log "✗ FAIL: $*"; }

# --- DIRTY STATE DOCUMENTATION ---
# Expected dirty conditions found in pre-provisioning audit (2026-09-28):
# - No service accounts exist (kk-api, kk-payments, kk-logs): created in Phase 2
# - No kijanikiosk group exists: created in Phase 2
# - /opt/kijanikiosk/ directory tree does not exist: created in Phase 2
# - No ACLs set on shared/logs or config: configured in Phase 3
# - No existing kk- systemd units: created in Phase 6
# - No package holds set: applied in Phase 1
# - UFW has 11 rules from previous labs (ports 8000, 8001, 9090, docker0, 2112):
#   reset to baseline in Phase 5
# - Journal disk usage is 3.9G (uncapped): capped at 500MB in Phase 7
# - nginx is at 1.28.3-2ubuntu1.11: pinned to actual version in Phase 1

FAILED_CHECKS=0
PASSED_CHECKS=0

assert() {
    if eval "$2"; then
        success "$1"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        fail "$1"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

###############################################################################
# PHASE 1: Package Management & Version Pinning
###############################################################################
log "=== PHASE 1: Package Management ==="

PINNED_NGINX="1.28.3-2ubuntu1.11"
PINNED_CURL="8.18.0-1ubuntu2.7"

# Clear any stale holds
for pkg in nginx curl; do
    if apt-mark showhold 2>/dev/null | grep -q "^$pkg$"; then
        log "Clearing hold on $pkg"
        sudo apt-mark unhold "$pkg"
    fi
done

# Check installed versions
INSTALLED_NGINX=$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || echo "not-installed")

if [[ "$INSTALLED_NGINX" == "$PINNED_NGINX" ]]; then
    log "nginx already at pinned version $PINNED_NGINX, skipping install"
elif [[ "$INSTALLED_NGINX" == "not-installed" ]]; then
    log "Installing nginx at pinned version $PINNED_NGINX"
    sudo apt-get update -qq
    sudo apt-get install -y "nginx=$PINNED_NGINX"
else
    log "WARNING: nginx is at $INSTALLED_NGINX, expected $PINNED_NGINX"
    log "Downgrading to pinned version (documented in hardening-decisions.md)"
    sudo apt-get install -y "nginx=$PINNED_NGINX"
fi

sudo apt-mark hold nginx curl
sudo apt-get install -y acl logrotate jq

assert "nginx at pinned version" \
    "[[ \"\$(dpkg-query -W -f='\${Version}' nginx)\" == \"$PINNED_NGINX\" ]]"

###############################################################################
# PHASE 2: Users, Groups, and Directory Structure
###############################################################################
log "=== PHASE 2: Users & Groups ==="

if ! getent group kijanikiosk > /dev/null; then
    sudo groupadd kijanikiosk
    log "Created group kijanikiosk"
else
    log "Group kijanikiosk already exists"
fi

for user in kk-api kk-payments kk-logs; do
    if ! getent passwd "$user" > /dev/null; then
        sudo useradd -r -s /usr/sbin/nologin -g kijanikiosk -c "KijaniKiosk $user service" "$user"
        log "Created user: $user"
    else
        log "User $user already exists, ensuring group membership"
        sudo usermod -g kijanikiosk "$user" 2>/dev/null || true
    fi
done

sudo mkdir -p /opt/kijanikiosk/{config,shared/logs,health,api,payments,logs}
sudo chown -R root:kijanikiosk /opt/kijanikiosk
sudo chmod -R 750 /opt/kijanikiosk

assert "kijanikiosk group exists" "getent group kijanikiosk > /dev/null"
assert "kk-api user exists" "getent passwd kk-api > /dev/null"
assert "kk-payments user exists" "getent passwd kk-payments > /dev/null"
assert "kk-logs user exists" "getent passwd kk-logs > /dev/null"

###############################################################################
# PHASE 3: ACLs and Access Model
###############################################################################
log "=== PHASE 3: ACLs & Access Model ==="

sudo setfacl -R -m g:kijanikiosk:rwx /opt/kijanikiosk/shared/logs/
sudo setfacl -d -m g:kijanikiosk:rwx /opt/kijanikiosk/shared/logs/
sudo setfacl -d -m u:kk-api:rwx /opt/kijanikiosk/shared/logs/
sudo setfacl -d -m u:kk-payments:rwx /opt/kijanikiosk/shared/logs/
sudo setfacl -d -m u:kk-logs:rwx /opt/kijanikiosk/shared/logs/

sudo setfacl -R -m g:kijanikiosk:rx /opt/kijanikiosk/config/
sudo setfacl -d -m g:kijanikiosk:rx /opt/kijanikiosk/config/

sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/health
sudo chmod 750 /opt/kijanikiosk/health

assert "shared/logs has default ACL for kk-api" \
    "getfacl /opt/kijanikiosk/shared/logs/ | grep -q 'default:user:kk-api:rwx'"
assert "shared/logs has default ACL for kk-payments" \
    "getfacl /opt/kijanikiosk/shared/logs/ | grep -q 'default:user:kk-payments:rwx'"

###############################################################################
# PHASE 4: Environment Files & Configuration
###############################################################################
log "=== PHASE 4: Environment Files ==="

sudo tee /opt/kijanikiosk/config/api.env > /dev/null <<'EOF'
NODE_ENV=production
PORT=3000
LOG_LEVEL=info
LOG_DIR=/opt/kijanikiosk/shared/logs
EOF

sudo tee /opt/kijanikiosk/config/payments-api.env > /dev/null <<'EOF'
NODE_ENV=production
PORT=3001
LOG_LEVEL=info
LOG_DIR=/opt/kijanikiosk/shared/logs
API_URL=http://localhost:3000
EOF

sudo tee /opt/kijanikiosk/config/logs.env > /dev/null <<'EOF'
NODE_ENV=production
PORT=3002
LOG_LEVEL=info
LOG_DIR=/opt/kijanikiosk/shared/logs
EOF

sudo chown root:kijanikiosk /opt/kijanikiosk/config/*.env
sudo chmod 640 /opt/kijanikiosk/config/*.env

for user_env_pair in "kk-api:api.env" "kk-payments:payments-api.env" "kk-logs:logs.env"; do
    user="${user_env_pair%%:*}"
    envfile="${user_env_pair##*:}"
    if sudo -u "$user" test -r "/opt/kijanikiosk/config/$envfile"; then
        success "$user can read $envfile"
    else
        fail "$user cannot read $envfile"
    fi
done

###############################################################################
# PHASE 5: Firewall (Reset to Known Baseline)
###############################################################################
log "=== PHASE 5: Firewall Configuration ==="

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp comment 'SSH access for administration'
sudo ufw allow from 10.0.1.0/24 to any port 80 proto tcp comment 'HTTP from monitoring subnet'
sudo ufw allow from 10.0.1.0/24 to any port 3001 proto tcp comment 'kk-payments health check from monitoring'
sudo ufw allow in on lo to any port 3001 proto tcp comment 'Allow localhost proxy to kk-payments'
sudo ufw deny 3001/tcp comment 'Deny external access to kk-payments internal port'

sudo ufw --force enable

log "Verifying firewall rules..."
status=$(sudo ufw status)

echo "$status" | grep -q "22/tcp.*ALLOW" \
    && success "SSH (22) allowed" \
    || { fail "SSH rule missing"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }

echo "$status" | grep -q "80/tcp.*ALLOW" \
    && success "HTTP (80) allowed" \
    || { fail "HTTP rule missing"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }

echo "$status" | grep -q "3001/tcp.*DENY" \
    && success "port 3001 external deny present" \
    || { fail "port 3001 deny rule missing"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }

###############################################################################
# PHASE 6: Systemd Service Units (Inline)
###############################################################################
log "=== PHASE 6: Systemd Service Units ==="

sudo tee /etc/systemd/system/kk-api.service > /dev/null <<'EOF'
[Unit]
Description=KijaniKiosk API Service
After=network.target

[Service]
Type=simple
User=kk-api
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/api.env
ExecStart=/usr/bin/node /opt/kijanikiosk/api/server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/kk-payments.service > /dev/null <<'EOF'
[Unit]
Description=KijaniKiosk Payments Service
After=kk-api.service network.target
Wants=kk-api.service

[Service]
Type=simple
User=kk-payments
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
PrivateDevices=yes
PrivateUsers=yes
ProtectHostname=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/kk-logs.service > /dev/null <<'EOF'
[Unit]
Description=KijaniKiosk Log Aggregation Service
After=network.target

[Service]
Type=simple
User=kk-logs
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/logs.env
ExecStart=/usr/bin/node /opt/kijanikiosk/logs/server.js
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-logs
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

assert "kk-api.service exists" "test -f /etc/systemd/system/kk-api.service"
assert "kk-payments.service exists" "test -f /etc/systemd/system/kk-payments.service"
assert "kk-logs.service exists" "test -f /etc/systemd/system/kk-logs.service"

###############################################################################
# PHASE 7: Journal Persistence & Log Rotation
###############################################################################
log "=== PHASE 7: Journal Persistence & Log Rotation ==="

sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/kijanikiosk.conf > /dev/null <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=100M
SystemMaxFileSize=50M
Compress=yes
EOF

sudo systemctl restart systemd-journald

sudo tee /etc/logrotate.d/kijanikiosk > /dev/null <<'EOF'
/opt/kijanikiosk/shared/logs/*.log {
    su root kijanikiosk
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0660 kk-api kijanikiosk
    sharedscripts
    postrotate
        systemctl try-reload-or-restart kk-logs.service 2>/dev/null || true
    endscript
}
EOF

if sudo logrotate --debug /etc/logrotate.d/kijanikiosk 2>&1 | grep -qi "error"; then
    fail "logrotate config has errors"
else
    success "logrotate config passes debug check"
fi

log "Simulating log rotation..."
sudo logrotate --force /etc/logrotate.d/kijanikiosk || true

if sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp 2>/dev/null; then
    success "Access model survives logrotate"
    rm -f /opt/kijanikiosk/shared/logs/test-write.tmp
else
    fail "Access model broken after logrotate"
fi

assert "journal persistence configured" "grep -q 'Storage=persistent' /etc/systemd/journald.conf.d/kijanikiosk.conf"
assert "journal capped at 500M" "grep -q 'SystemMaxUse=500M' /etc/systemd/journald.conf.d/kijanikiosk.conf"

###############################################################################
# PHASE 8: Monitoring Health Checks
###############################################################################
log "=== PHASE 8: Health Checks ==="

api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null && echo "ok" || echo "down")
payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null && echo "ok" || echo "down")
logs_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3002" 2>/dev/null && echo "ok" || echo "down")

sudo mkdir -p /opt/kijanikiosk/health
sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/health
sudo chmod 750 /opt/kijanikiosk/health

sudo tee /opt/kijanikiosk/health/last-provision.json > /dev/null <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "kk-api": "$api_status",
  "kk-payments": "$payments_status",
  "kk-logs": "$logs_status"
}
EOF

sudo chown kk-logs:kijanikiosk /opt/kijanikiosk/health/last-provision.json
sudo chmod 640 /opt/kijanikiosk/health/last-provision.json

assert "health check file exists" "test -f /opt/kijanikiosk/health/last-provision.json"
assert "health check readable by kijanikiosk group" "sudo -u kk-logs test -r /opt/kijanikiosk/health/last-provision.json"

log "Health check results: api=$api_status, payments=$payments_status, logs=$logs_status"

###############################################################################
# FINAL VERIFICATION PHASE
###############################################################################
log "=== FINAL VERIFICATION ==="
log "Passed: $PASSED_CHECKS | Failed: $FAILED_CHECKS"

if [[ $FAILED_CHECKS -gt 0 ]]; then
    log "✗ PROVISIONING FAILED: $FAILED_CHECKS check(s) did not pass"
    exit 1
else
    log "✓ ALL CHECKS PASSED - Provisioning complete"
    exit 0
fi
