#!/bin/bash

LOGFILE="/var/log/secure_sudo_script.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/sudo_config_backup_$TIMESTAMP"

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
        sudo timeshift --create --comments "Pre-change snapshot - $TIMESTAMP" --tags D
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

# --- Step 1: Ensure sudo is installed ---
if prompt_confirm "Ensure 'sudo' is installed?"; then
    log "Installing sudo..."
    sudo apt update && sudo apt install sudo -y
    check_command_success $?
fi

# --- Step 2: Verify users in sudo group ---
log "Users in 'sudo' group:"
getent group sudo | tee -a "$LOGFILE"

# --- Step 3: Add user to sudo group ---
read -rp "Enter username to add to sudo group (leave blank to skip): " USERNAME
if [[ -n "$USERNAME" ]]; then
    if prompt_confirm "Add $USERNAME to sudo group?"; then
        sudo usermod -aG sudo "$USERNAME"
        check_command_success $?
        log "$USERNAME added to sudo group."
    fi
fi

# --- Step 4: Harden sudo configuration ---
if prompt_confirm "Harden /etc/sudoers configuration?"; then
    SUDOERS_FILE="/etc/sudoers"
    backup_file "$SUDOERS_FILE"

    sudo bash -c "grep -qxF 'Defaults use_pty' $SUDOERS_FILE || echo 'Defaults use_pty' >> $SUDOERS_FILE"
    sudo bash -c "grep -qxF 'Defaults log_input,log_output' $SUDOERS_FILE || echo 'Defaults log_input,log_output' >> $SUDOERS_FILE"
    sudo bash -c "grep -qxF 'Defaults logfile=\"/var/log/sudo.log\"' $SUDOERS_FILE || echo 'Defaults logfile=\"/var/log/sudo.log\"' >> $SUDOERS_FILE"
    log "Sudoers hardened."
fi

# --- Step 5: Deny su to non-sudo users ---
if prompt_confirm "Restrict 'su' to sudo group only?"; then
    sudo dpkg-statoverride --update --add root sudo 4750 /bin/su
    check_command_success $?
    log "'su' access restricted to sudo group."
fi

# --- Step 6: Disable root login ---
if prompt_confirm "Disable root login (lock root account)?"; then
    sudo passwd -l root
    check_command_success $?
    log "Root account locked."
fi

# --- TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

# --- Step 7: Tests ---
log "Running test cases..."

echo -e "\n[Test] Running: sudo -l"
sudo -l

echo -e "\n[Test] Attempting: su - (as non-sudo user)"
if prompt_confirm "Switch to non-sudo user for test? (requires passwordless access)"; then
    read -rp "Enter non-sudo username: " NON_SUDO_USER
    sudo -u "$NON_SUDO_USER" bash -c 'su -'
fi

echo -e "\n[Test] Attempting: apt install cowsay (without sudo)"
if prompt_confirm "Test installing package without sudo?"; then
    apt install cowsay || log "Permission denied as expected (non-root)"
fi

echo -e "\n[Test] Running: sudo -i"
sudo -i exit

echo -e "\n[Test] Reading sudo log (/var/log/sudo.log)"
sudo cat /var/log/sudo.log | tail -n 10

echo -e "\n[Test] Attempting: passwd root"
passwd root || log "Expected failure due to locked root account."

log "✅ All steps completed."

exit 0
