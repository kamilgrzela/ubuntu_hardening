#!/bin/bash

# ------------------------------------------------------------------------
# Script Name: configure_ufw.sh
#
# Description:
# This script installs and configures the Uncomplicated Firewall (UFW)
# with a default-deny policy and explicit allow rules for essential services.
#
# Steps performed:
#   - Install UFW
#   - Set default firewall policy (deny incoming, allow outgoing)
#   - Allow specific TCP/UDP ports for required services:
#       - SSH (22, 10022)
#       - MQTT (1883, 8883)
#       - ROS2 (7400 TCP, 7400/UDP, 7410-7465/UDP)
#       - Diagnostic tools (7070, 8001)
#       - Grafana (3000)
#       - Multicast service (5353/UDP, 53542/UDP)
#   - Enable UFW
#   - Display firewall status
#   - Optionally create a TimeShift snapshot
#
# Usage:
#   chmod +x configure_ufw.sh
#   sudo ./configure_ufw.sh
#
# Author:
#   Kamil Grzela
# ------------------------------------------------------------------------

LOGFILE="/var/log/configure_ufw.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/ufw_config_backup_$TIMESTAMP"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOGFILE"
}

prompt_confirm() {
    read -r -p "$1 [y/N]: " response
    [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
}

run_timeshift_snapshot() {
    if command -v timeshift >/dev/null 2>&1; then
        sudo timeshift --create --comments "UFW configuration - $TIMESTAMP" --tags D
        log "TimeShift snapshot created."
    else
        log "TimeShift not available."
    fi
}

check_command_success() {
    if [[ $1 -ne 0 ]]; then
        log "ERROR: Last command failed. Exiting."
        exit 1
    fi
}

# --- Step 1: Install UFW ---
if prompt_confirm "Install UFW now?"; then
    sudo apt update
    sudo apt install ufw -y
    check_command_success $?
    log "UFW installed successfully."
fi

# --- Step 2: Set default policy ---
if prompt_confirm "Set default firewall policy (deny incoming, allow outgoing)?"; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    log "Default policy set."
fi

# --- Step 3: Allow essential TCP/UDP ports ---

log "Allowing required ports for system operation..."

# TCP Ports
sudo ufw allow 22/tcp       # SSH default port
sudo ufw allow 10022/tcp    # Custom SSH port (used in earlier hardening)
sudo ufw allow 1883/tcp     # MQTT (not secured)
sudo ufw allow 8883/tcp     # MQTT over TLS
sudo ufw allow 7400/tcp     # ROS2
sudo ufw allow 7070/tcp     # AnyDesk (remote access)
sudo ufw allow 8001/tcp     # Diag_viz_adapte (log collection)
sudo ufw allow 3000/tcp     # Grafana (ensure binding to safe interface)

# UDP Ports
sudo ufw allow 7400/udp     # ROS2
sudo ufw allow 5353/udp     # mDNS / Multicast DNS
sudo ufw allow 53542/udp    # Custom multicast/discovery (if used)
sudo ufw allow 7410:7465/udp # ROS2 or DDS dynamic discovery range

log "Port rules applied."

# --- Step 4: Enable UFW ---
if prompt_confirm "Enable UFW now?"; then
    sudo ufw --force enable
    check_command_success $?
    log "UFW enabled."
fi

# --- Step 5: Show status ---
log "Current UFW status:"
sudo ufw status verbose | tee -a "$LOGFILE"

# --- Step 6: Optional TimeShift snapshot ---
if prompt_confirm "Create TimeShift snapshot now?"; then
    run_timeshift_snapshot
fi

log "✅ UFW firewall configuration completed."

exit 0
