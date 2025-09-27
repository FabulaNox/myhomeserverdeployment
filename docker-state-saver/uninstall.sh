#!/usr/bin/env bash
# Uninstaller for the Docker State Saver service.
# This script MUST be run with sudo or as root.

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Please use 'sudo ./uninstall.sh'"
  exit 1
fi

echo ">>> Uninstalling Docker State Saver..."

# --- Define System Paths ---
BIN_PATH="/usr/local/bin/docker-state-saver.sh"
BACKUP_SCRIPT_PATH="/usr/local/bin/docker-volume-backup.sh"
UNINSTALL_SCRIPT_PATH="/usr/local/bin/uninstall.sh"
CONFIG_DIR="/etc/docker-state-saver"
SERVICE_PATH="/etc/systemd/system/docker-state-saver.service"
STATE_DIR="/var/lib/docker-state-saver"

# 1. Stop and disable the systemd service
echo "--> Stopping and disabling systemd service..."
systemctl stop docker-state-saver.service || true
systemctl disable docker-state-saver.service || true
systemctl daemon-reload

# 2. Remove all installed files
echo "--> Removing installed files..."
rm -f "$BIN_PATH"
rm -f "$BACKUP_SCRIPT_PATH"
rm -f "$SERVICE_PATH"
rm -rf "$CONFIG_DIR"

# 3. Remove state directory
echo "--> Removing state directory..."
rm -rf "$STATE_DIR"

# Note: We do NOT remove the backup directory or log file automatically.
# The user should do this manually if they want to delete their data.

# 4. Remove this uninstaller
rm -f "$UNINSTALL_SCRIPT_PATH"

echo ""
echo ">>> Uninstallation complete."
echo "The backup directory and log file have NOT been removed. You can remove them manually:"
echo "  - Backups: /var/backups/docker-volumes"
echo "  - Log: /var/log/docker-state-saver.log"
