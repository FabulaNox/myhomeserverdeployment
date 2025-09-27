#!/usr/bin/env bash
# Installer for the Docker State Saver service.
# This script MUST be run with sudo or as root.

set -e

# --- Permission Check ---
if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Please use 'sudo ./install.sh'"
  exit 1
fi

echo ">>> Installing Docker State Saver..."

# --- Define System Paths ---
BIN_PATH="/usr/local/bin/docker-state-saver.sh"
CONFIG_DIR="/etc/docker-state-saver"
CONFIG_PATH="${CONFIG_DIR}/saver.conf"
SERVICE_PATH="/etc/systemd/system/docker-state-saver.service"

# --- Source Configuration to get STATE_DIR ---
# shellcheck source=/dev/null
source ./saver.conf
if [[ -z "$STATE_DIR" ]]; then
    echo "ERROR: STATE_DIR is not defined in saver.conf"
    exit 1
fi

# 1. Create necessary directories
echo "--> Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$STATE_DIR"

# 2. Copy files to their system locations
echo "--> Copying files..."
cp ./docker-state-saver.sh "$BIN_PATH"
cp ./saver.conf "$CONFIG_PATH"
cp ./docker-state-saver.service "$SERVICE_PATH"

# 3. Set correct file permissions
echo "--> Setting permissions..."
chmod 755 "$BIN_PATH"      # Executable for the main script
chmod 644 "$CONFIG_PATH"   # Readable by all, writable only by root
chmod 644 "$SERVICE_PATH"  # Standard systemd service permissions

# 4. Reload systemd daemon and enable the new service
echo "--> Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable docker-state-saver.service

echo ""
echo ">>> Installation complete."
echo "The 'docker-state-saver' service is now enabled and will run on system startup and shutdown."
echo "You can check its status with: systemctl status docker-state-saver"
echo "You can view its logs with:   tail -f /var/log/docker-state-saver.log"
