#!/usr/bin/env bash
# Uninstaller for the Docker State Saver service.
# This script MUST be run with sudo or as root.

set -e

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Please use 'sudo ./uninstall.sh'"
  exit 1
fi

echo ">>> Uninstalling Docker State Saver..."

# --- Load Configuration from the installed saver.conf ---
# This is the one place a path is hardcoded, to find the config file itself.
INSTALLED_CONFIG_FILE="/etc/docker-state-saver/saver.conf"
if [[ -f "$INSTALLED_CONFIG_FILE" ]]; then
    source "$INSTALLED_CONFIG_FILE"
else
    echo "WARNING: Main config file not found. Cannot proceed with a clean uninstall."
    exit 1
fi

# --- Construct Full Paths from sourced variables ---
BIN_PATH="${BIN_DIR}/${MAIN_SCRIPT_NAME}"
BACKUP_SCRIPT_PATH="${BIN_DIR}/${BACKUP_SCRIPT_NAME}"
UNINSTALL_SCRIPT_PATH="${BIN_DIR}/${UNINSTALL_SCRIPT_NAME}"
SERVICE_PATH="${SERVICE_DIR}/${SERVICE_NAME}"

# 1. Stop and disable the systemd service
echo "--> Stopping and disabling systemd service..."
systemctl stop "$SERVICE_NAME" || true
systemctl disable "$SERVICE_NAME" || true
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

# 4. Remove this uninstaller
rm -f "$UNINSTALL_SCRIPT_PATH"

echo ""
echo ">>> Uninstallation complete."
echo "The backup directory ($BACKUP_DIR) and log file ($LOG_FILE) have NOT been removed."
