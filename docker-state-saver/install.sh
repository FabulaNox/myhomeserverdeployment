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
BACKUP_SCRIPT_PATH="/usr/local/bin/docker-volume-backup.sh"
UNINSTALL_SCRIPT_PATH="/usr/local/bin/uninstall.sh"
CONFIG_DIR="/etc/docker-state-saver"
CONFIG_PATH="${CONFIG_DIR}/saver.conf"
SERVICE_PATH="/etc/systemd/system/docker-state-saver.service"

# --- Source Configuration to get directories ---
# Use a simple parser for INI sections
STATE_DIR=$(sed -n -e 's/^\s*STATE_DIR\s*=\s*"\?\([^"]*\)"\?/\1/p' ./saver.conf)
BACKUP_DIR=$(sed -n -e 's/^\s*BACKUP_DIR\s*=\s*"\?\([^"]*\)"\?/\1/p' ./saver.conf)
if [[ -z "$STATE_DIR" ]] || [[ -z "$BACKUP_DIR" ]]; then
    echo "ERROR: STATE_DIR or BACKUP_DIR is not defined in saver.conf"
    exit 1
fi

# 1. Create necessary directories
echo "--> Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$STATE_DIR"
mkdir -p "$BACKUP_DIR"

# 2. Copy files to their system locations
echo "--> Copying files..."
cp ./docker-state-saver.sh "$BIN_PATH"
cp ./docker-volume-backup.sh "$BACKUP_SCRIPT_PATH"
cp ./uninstall.sh "$UNINSTALL_SCRIPT_PATH"
cp ./saver.conf "$CONFIG_PATH"
cp ./docker-state-saver.service "$SERVICE_PATH"

# 3. Set correct file permissions
echo "--> Setting permissions..."
chmod 755 "$BIN_PATH"
chmod 755 "$BACKUP_SCRIPT_PATH"
chmod 755 "$UNINSTALL_SCRIPT_PATH"
chmod 644 "$CONFIG_PATH"
chmod 644 "$SERVICE_PATH"

# 4. Auto-configure Docker Desktop user if installed via sudo
if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
    echo "--> Detected sudo user '$SUDO_USER'. Configuring for Docker Desktop."
    sed -i "s/DOCKER_DESKTOP_USER=\".*\"/DOCKER_DESKTOP_USER=\"$SUDO_USER\"/" "$CONFIG_PATH"
else
    echo "--> No sudo user detected. Clearing Docker Desktop user setting."
    sed -i "s/DOCKER_DESKTOP_USER=\".*\"/DOCKER_DESKTOP_USER=\"\"/" "$CONFIG_PATH"
fi

# 5. Reload systemd daemon and enable the new service
echo "--> Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable docker-state-saver.service

echo ""
echo ">>> Installation complete."
echo "The 'docker-state-saver' service is now enabled."
echo "An uninstaller has been placed at: $UNINSTALL_SCRIPT_PATH"
echo ""
echo "--- Next Steps: Automated Backups ---"
echo "To enable automated backups, you must set up a cron job."
echo "1. Edit the root crontab: sudo crontab -e"
echo "2. Add a line to schedule the backup script. For example, to run daily at 3 AM:"
echo "   0 3 * * * $BACKUP_SCRIPT_PATH"
echo ""
echo "You can view logs with: tail -f /var/log/docker-state-saver.log"
