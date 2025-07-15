#!/bin/bash

# ------------------------------------------------------------------------
# Script Name: configure_fail2ban.sh
#
# Description:
# This script installs and configures Fail2Ban to protect the system
# from brute-force attacks, primarily via SSH. It performs the following:
#
#   - Installs fail2ban package
#   - Creates a local configuration file from jail.conf
#   - Configures default ban settings and enables SSH protection
#   - Sets UFW as the IP banning mechanism
#   - Restarts and enables the fail2ban service
#   - Optionally creates a TimeShift snapshot
#   - Logs all steps and outputs instructions for manual testing
#
# Usage:
#   chmod +x install_fail2ban.sh
#   sudo ./install_fail2ban.sh
#
# Author:
#   Kamil Grzela
# ------------------------------------------------------------------------

LOGFILE="/var/log/install_fail2ban.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/fail2ban_backup_$TIMESTAMP"
JAIL_LOCAL="/etc/fail2ban/jail.local"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOGFILE"
}

prompt_confirm() {
    read -r -p "$1 [y/N]: " response
    [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
}

run_timeshift_snapshot() {
    if command -v timeshift >/dev/null 2>&1; then
        sudo timeshift --create --comments "Fail2Ban configuration - $TIMESTAMP" --tags D
        log "TimeShift snapshot created."
    else
        log "TimeShift is not installed or not available."
    fi
}

check_command_success() {
    if [[ $1 -ne 0 ]]; then
        log "❌ ERROR: Last command failed. Exiting."
        exit 1
    fi
}

# --- Step 1: Install fail2ban ---
if prompt_confirm "Install Fail2Ban now?"; then
    sudo apt update
    sudo apt install fail2ban -y
    check_command_success $?
    log "✅ Fail2Ban installed."
fi

# --- Step 2: Create jail.local ---
if prompt_confirm "Create and configure jail.local file?"; then
    if [[ -f "$JAIL_LOCAL" ]]; then
        cp "$JAIL_LOCAL" "$BACKUP_DIR/jail.local.bak"
        log "Backup of existing jail.local saved."
    else
        sudo cp /etc/fail2ban/jail.conf "$JAIL_LOCAL"
        log "Created jail.local from jail.conf"
    fi

    sudo tee "$JAIL_LOCAL" >/dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
banaction = ufw

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd
EOF

    log "Configured $JAIL_LOCAL with SSH protection and UFW banning."
fi

# --- Step 3: Restart and enable fail2ban ---
if prompt_confirm "Restart and enable fail2ban service?"; then
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
    check_command_success $?
    log "✅ Fail2Ban restarted and enabled."
fi

# --- Step 4: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 5: Manual test instructions ---
log "🧪 Manual test instructions:"
echo -e "
✅ Check Fail2Ban version:
    fail2ban-client -V

✅ Check active jails:
    fail2ban-client status

❌ Simulate 6 failed SSH logins (from another IP):
    Expected: IP will be banned

🔍 Check SSH jail status and banned IPs:
    fail2ban-client status sshd

🔐 Verify UFW shows the IP is blocked:
    sudo ufw status
" | tee -a "$LOGFILE"

log "✅ Fail2Ban configuration completed (status previously: NOT done)."

exit 0
