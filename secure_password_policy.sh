#!/bin/bash

LOGFILE="/var/log/secure_password_policy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/pam_config_backup_$TIMESTAMP"

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
        sudo timeshift --create --comments "Password policy snapshot - $TIMESTAMP" --tags D
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

# --- Step 1: Install required PAM module ---
if prompt_confirm "Install 'libpam-pwquality' module?"; then
    log "Installing libpam-pwquality..."
    sudo apt update && sudo apt install libpam-pwquality -y
    check_command_success $?
fi

# --- Step 2: Configure /etc/security/pwquality.conf ---
PWQUALITY_CONF="/etc/security/pwquality.conf"
if prompt_confirm "Configure password strength policy in $PWQUALITY_CONF?"; then
    backup_file "$PWQUALITY_CONF"
    sudo tee "$PWQUALITY_CONF" >/dev/null <<EOF
minlen = 15
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
maxrepeat = 3
reject_username = 1
EOF
    log "Updated $PWQUALITY_CONF with strict password policy."
fi

# --- Step 3: Configure /etc/login.defs ---
LOGIN_DEFS="/etc/login.defs"
if prompt_confirm "Configure password expiry policy in $LOGIN_DEFS?"; then
    backup_file "$LOGIN_DEFS"
    sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   180/' "$LOGIN_DEFS"
    sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   0/' "$LOGIN_DEFS"
    sudo sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' "$LOGIN_DEFS"
    log "Updated password expiration policy in $LOGIN_DEFS."
fi

# --- Step 4: Integrate with PAM /etc/pam.d/common-password ---
PAM_CONF="/etc/pam.d/common-password"
if prompt_confirm "Integrate pam_pwquality into PAM config in $PAM_CONF?"; then
    backup_file "$PAM_CONF"

    if grep -q "pam_pwquality.so" "$PAM_CONF"; then
        sudo sed -i 's|pam_pwquality.so.*|pam_pwquality.so retry=3|' "$PAM_CONF"
        log "Updated existing pam_pwquality.so line."
    else
        sudo sed -i '/^password\s\+requisite/a password requisite pam_pwquality.so retry=3' "$PAM_CONF"
        log "Inserted pam_pwquality.so line."
    fi
fi

# --- TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 5: Test password policy ---
log "Running test cases for password policy..."

read -rp "Enter test username to run password tests (must exist): " TESTUSER

if id "$TESTUSER" >/dev/null 2>&1; then
    declare -a TEST_PASSWORDS=(
        "Pass12!"            # too short
        "nouppercase1!"      # missing uppercase
        "NOLOWERCASE1!"      # missing lowercase
        "NoDigits!"          # missing digits
        "NoSpecial1"         # missing special characters
        "$TESTUSER"          # same as username
        "Compliant1!Password"  # valid
    )

    for pw in "${TEST_PASSWORDS[@]}"; do
        echo -e "\n[Test] Trying password: '$pw'"
        echo -e "$pw\n$pw" | sudo passwd "$TESTUSER" >/tmp/passwd_output 2>&1
        if grep -q "BAD PASSWORD" /tmp/passwd_output || grep -q "password is too simple" /tmp/passwd_output; then
            log "Rejected as expected: '$pw'"
        elif grep -q "successfully updated" /tmp/passwd_output; then
            log "Accepted (OK): '$pw'"
        else
            cat /tmp/passwd_output
            log "Manual check required for: '$pw'"
        fi
    done
else
    log "User $TESTUSER does not exist. Skipping tests."
fi

log "✅ All steps completed."

exit 0
