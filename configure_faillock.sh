#!/bin/bash

LOGFILE="/var/log/configure_faillock.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/faillock_config_backup_$TIMESTAMP"

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
        sudo timeshift --create --comments "faillock configuration - $TIMESTAMP" --tags D
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

# --- Step 1: Edit /etc/pam.d/common-auth ---
AUTH_FILE="/etc/pam.d/common-auth"
if prompt_confirm "Modify $AUTH_FILE to enable pam_faillock?"; then
    backup_file "$AUTH_FILE"

    if ! grep -q "pam_faillock.so preauth" "$AUTH_FILE"; then
        sudo sed -i '1i auth required pam_faillock.so preauth' "$AUTH_FILE"
        sudo sed -i '2i auth [success=1 default=bad] pam_unix.so' "$AUTH_FILE"
        sudo sed -i '3i auth [default=die] pam_faillock.so authfail' "$AUTH_FILE"
        log "Inserted faillock rules into $AUTH_FILE"
    else
        log "pam_faillock already configured in $AUTH_FILE"
    fi
fi

# --- Step 2: Edit /etc/pam.d/common-account ---
ACCOUNT_FILE="/etc/pam.d/common-account"
if prompt_confirm "Add faillock to $ACCOUNT_FILE?"; then
    backup_file "$ACCOUNT_FILE"
    if ! grep -q "pam_faillock.so" "$ACCOUNT_FILE"; then
        echo "account required pam_faillock.so" | sudo tee -a "$ACCOUNT_FILE" >/dev/null
        log "Added faillock to $ACCOUNT_FILE"
    else
        log "pam_faillock already present in $ACCOUNT_FILE"
    fi
fi

# --- Step 3: Configure /etc/security/faillock.conf ---
FAILLOCK_CONF="/etc/security/faillock.conf"
if prompt_confirm "Configure $FAILLOCK_CONF?"; then
    backup_file "$FAILLOCK_CONF"
    sudo tee "$FAILLOCK_CONF" >/dev/null <<EOF
deny = 5
unlock_time = 900
fail_interval = 900
even_deny_root
EOF
    log "Configured $FAILLOCK_CONF with recommended settings"
fi

# --- Step 4: TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 5: Test instructions ---
log "⚠️ To test faillock manually, perform the following steps:"
echo -e "
1. SSH into the system and fail login 5 times with a wrong password.
2. Expected: Account gets locked.
3. To check lock status for a user:
   faillock --user <username>

4. To clear lock manually:
   faillock --user <username> --reset
" | tee -a "$LOGFILE"

log "✅ Faillock configuration completed."

exit 0
