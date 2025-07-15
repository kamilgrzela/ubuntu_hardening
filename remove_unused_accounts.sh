#!/bin/bash

LOGFILE="/var/log/remove_unused_accounts.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/user_cleanup_backup_$TIMESTAMP"

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
        sudo timeshift --create --comments "User cleanup snapshot - $TIMESTAMP" --tags D
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

# --- Step 1: Review users ---
log "Current list of users with UID >= 1000 (excluding system users):"
cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 { print $1 }' | tee -a "$LOGFILE"

# --- Step 2: Remove unused accounts ---
if prompt_confirm "Do you want to remove unused accounts now?"; then
    while true; do
        read -rp "Enter username to delete (leave empty to finish): " USERNAME
        if [[ -z "$USERNAME" ]]; then
            break
        fi

        if id "$USERNAME" >/dev/null 2>&1; then
            if prompt_confirm "Confirm deletion of user '$USERNAME' and their home directory?"; then
                sudo deluser --remove-home "$USERNAME"
                check_command_success $?
                log "User '$USERNAME' removed."
            fi
        else
            log "User '$USERNAME' does not exist."
        fi
    done
fi

# --- Step 3: Set INACTIVE=30 in login.defs ---
LOGIN_DEFS="/etc/login.defs"
if prompt_confirm "Set INACTIVE=30 in $LOGIN_DEFS?"; then
    backup_file "$LOGIN_DEFS"
    if grep -q "^INACTIVE" "$LOGIN_DEFS"; then
        sudo sed -i 's/^INACTIVE.*/INACTIVE=30/' "$LOGIN_DEFS"
    else
        echo "INACTIVE=30" | sudo tee -a "$LOGIN_DEFS" >/dev/null
    fi
    log "Set INACTIVE=30 in $LOGIN_DEFS"
else
    log "Skipped setting INACTIVE=30 per project decision."
fi

# --- Step 4: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 5: Tests ---
log "Running test cases..."

echo -e "\n[Test] Reviewing current users (UID >= 1000):"
cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 { print $1 }' | tee -a "$LOGFILE"

echo -e "\n[Test] Checking INACTIVE setting in $LOGIN_DEFS:"
grep "^INACTIVE" "$LOGIN_DEFS" | tee -a "$LOGFILE"

log "✅ All steps completed."

exit 0
