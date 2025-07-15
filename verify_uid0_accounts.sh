#!/bin/bash

LOGFILE="/var/log/verify_uid0_accounts.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/uid0_check_$TIMESTAMP"

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
        sudo timeshift --create --comments "UID 0 account fix - $TIMESTAMP" --tags D
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

# --- Step 1: Check UID 0 accounts ---
log "Checking for accounts with UID 0..."
UID0_USERS=$(awk -F: '($3 == 0) { print $1 }' /etc/passwd)

echo "$UID0_USERS" | tee -a "$LOGFILE"

# --- Step 2: Take action on non-root UID 0 accounts ---
for user in $UID0_USERS; do
    if [[ "$user" != "root" ]]; then
        log "⚠️  Found non-root account with UID 0: $user"

        if prompt_confirm "Do you want to REMOVE user '$user'?"; then
            sudo deluser --remove-home "$user"
            check_command_success $?
            log "User '$user' removed."
        elif prompt_confirm "Do you want to CHANGE UID of '$user' to 1001?"; then
            sudo usermod -u 1001 "$user"
            check_command_success $?
            log "User '$user' UID changed to 1001."
        else
            log "No action taken on user '$user'."
        fi
    fi
done

# --- Step 3: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 4: Final Test ---
log "Running test: UID 0 account verification..."
awk -F: '($3 == 0) { print $1 }' /etc/passwd | tee -a "$LOGFILE"

log "✅ All steps completed."

exit 0
