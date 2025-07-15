#!/bin/bash


# ------------------------------------------------------------------------
# Script Name: configure_ssh_access_group.sh
#
# Description:
# This script configures SSH server access to allow only specific users or
# groups by updating the sshd_config file. It performs the following actions:
#
#   - Creates a dedicated group (default: 'sshallowed') for SSH access
#   - Adds specified users to that group
#   - Updates the SSH daemon configuration:
#       - Sets a custom port (10022)
#       - Defines ListenAddress (default: 0.0.0.0)
#       - Sets LogLevel to INFO
#       - Applies the AllowGroups directive
#   - Removes any existing AllowUsers directive to avoid conflict
#   - Restarts the SSH service (optional)
#   - Creates a TimeShift snapshot (optional)
#   - Logs all actions to /var/log/configure_ssh_access_group.log
#   - Provides manual test instructions for validation
#
# Usage:
#   Run as root or with sudo:
#     chmod +x configure_ssh_access_group.sh
#     sudo ./configure_ssh_access_group.sh
#
# Tested on:
#   Debian-based systems (Ubuntu, Debian)
#
# Author:
#   Kamil Grzela
# ------------------------------------------------------------------------




LOGFILE="/var/log/configure_ssh_access_group.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/ssh_group_config_backup_$TIMESTAMP"
SSHD_CONFIG="/etc/ssh/sshd_config"

SSH_GROUP="sshallowed"  # default group name

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
        sudo timeshift --create --comments "SSH group access config - $TIMESTAMP" --tags D
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

# --- Step 1: Create SSH group ---
if ! getent group "$SSH_GROUP" >/dev/null; then
    if prompt_confirm "Create SSH group '$SSH_GROUP'?"; then
        sudo groupadd "$SSH_GROUP"
        check_command_success $?
        log "Group '$SSH_GROUP' created."
    fi
else
    log "Group '$SSH_GROUP' already exists."
fi

# --- Step 2: Add users to SSH group ---
while true; do
    read -rp "Enter username to add to '$SSH_GROUP' (leave empty to finish): " USERNAME
    [[ -z "$USERNAME" ]] && break
    if id "$USERNAME" >/dev/null 2>&1; then
        sudo usermod -aG "$SSH_GROUP" "$USERNAME"
        check_command_success $?
        log "User '$USERNAME' added to group '$SSH_GROUP'."
    else
        log "User '$USERNAME' does not exist."
    fi
done

# --- Step 3: Modify sshd_config ---
if prompt_confirm "Modify SSH config at $SSHD_CONFIG?"; then
    backup_file "$SSHD_CONFIG"

    sudo sed -i 's/^#\?Port .*/Port 10022/' "$SSHD_CONFIG"
    sudo sed -i 's/^#\?ListenAddress .*/ListenAddress 0.0.0.0/' "$SSHD_CONFIG"
    sudo sed -i 's/^#\?LogLevel .*/LogLevel INFO/' "$SSHD_CONFIG"

    # Remove AllowUsers if present (to avoid conflict)
    sudo sed -i '/^AllowUsers/d' "$SSHD_CONFIG"

    if grep -q "^AllowGroups" "$SSHD_CONFIG"; then
        sudo sed -i "s/^AllowGroups.*/AllowGroups $SSH_GROUP/" "$SSHD_CONFIG"
    else
        echo "AllowGroups $SSH_GROUP" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi

    log "SSHD config updated: Port 10022, AllowGroups $SSH_GROUP, ListenAddress 0.0.0.0, LogLevel INFO"
fi

# --- Step 4: Restart SSH service ---
if prompt_confirm "Restart SSH service now?"; then
    sudo systemctl restart ssh
    check_command_success $?
    log "SSH service restarted."
else
    log "SSH restart skipped."
fi

# --- Step 5: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 6: Manual test instructions ---
log "⚠️ Manual test instructions:"
echo -e "
✅ Check SSH config:
    sudo sshd -T | grep -E 'port|allowgroups|listenaddress|loglevel'

✅ Attempt SSH login on port 10022:
    ssh -p 10022 <allowed_user>@<host>

❌ Attempt login as user not in '$SSH_GROUP' group → should fail

🔍 View denied logins:
    sudo grep 'sshd' /var/log/auth.log | grep 'Failed'
" | tee -a "$LOGFILE"

log "✅ SSH group-based access control configured (status previously: NOT done)."

exit 0
