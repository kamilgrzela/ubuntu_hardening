#!/bin/bash

LOGFILE="/var/log/disable_root_ssh.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/ssh_config_backup_$TIMESTAMP"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOGFILE"
}

prompt_confirm() {
    read -r -p "$1 [y/N]: " response
    [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
}

backup_file() {
    FILE=$1
    mkdir -p "$BACKUP_DIR"
    cp -a "$FILE" "$BACKUP_DIR"
    log "Backup of $FILE saved to $BACKUP_DIR"
}

run_timeshift_snapshot() {
    if command -v timeshift >/dev/null 2>&1; then
        sudo timeshift --create --comments "SSH root login disabled - $TIMESTAMP" --tags D
        log "TimeShift snapshot created."
    else
        log "TimeShift is not installed or not found!"
    fi
}

check_command_success() {
    if [[ $1 -ne 0 ]]; then
        log "ERROR: Last command failed. Exiting."
        exit 1
    fi
}

# --- Step 1: Update sshd_config ---
SSHD_CONFIG="/etc/ssh/sshd_config"

if prompt_confirm "Disable root login over SSH in $SSHD_CONFIG?"; then
    backup_file "$SSHD_CONFIG"

    if grep -q "^#PermitRootLogin" "$SSHD_CONFIG"; then
        sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    elif grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin no" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    log "'PermitRootLogin no' set in $SSHD_CONFIG"
fi

# --- Step 2: Restart SSH ---
if prompt_confirm "Restart SSH service now?"; then
    sudo systemctl restart ssh
    check_command_success $?
    log "SSH service restarted successfully."
else
    log "SSH service restart skipped. Please do it manually."
fi

# --- Step 3: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 4: Test Instructions ---
log "⚠️ Manual test instructions:"
echo -e "
Test 1: Attempt SSH login as root from another machine or terminal
Command: ssh root@<hostname>

Expected result: Login is denied with message such as 'Permission denied'.

You can also check current SSH configuration:
sudo sshd -T | grep permitrootlogin
" | tee -a "$LOGFILE"

log "✅ SSH root login restriction configured (status previously: NOT done)."

exit 0
