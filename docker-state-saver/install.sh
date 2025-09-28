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

# --- Source the local configuration file to get all paths and names ---
source ./saver.conf

# --- Construct Full Paths from sourced variables ---
BIN_PATH="${BIN_DIR}/${MAIN_SCRIPT_NAME}"
BACKUP_SCRIPT_PATH="${BIN_DIR}/${BACKUP_SCRIPT_NAME}"
UNINSTALL_SCRIPT_PATH="${BIN_DIR}/${UNINSTALL_SCRIPT_NAME}"
CONFIG_PATH="${CONFIG_DIR}/${CONFIG_NAME}"
SERVICE_PATH="${SERVICE_DIR}/${SERVICE_NAME}"

# 1. Create necessary directories
echo "--> Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$STATE_DIR"
mkdir -p "$BACKUP_DIR"

# 2. Copy script and config files
echo "--> Copying files..."
cp ./"$MAIN_SCRIPT_NAME" "$BIN_PATH"
cp ./"$BACKUP_SCRIPT_NAME" "$BACKUP_SCRIPT_PATH"
cp ./"$UNINSTALL_SCRIPT_NAME" "$UNINSTALL_SCRIPT_PATH"
cp ./"$CONFIG_NAME" "$CONFIG_PATH"

# 3. Create systemd service file dynamically
echo "--> Creating systemd service file..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Docker State Saver - Persist and Restore Running Containers
Requires=docker.socket
After=docker.socket
Before=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${BIN_PATH} restore
ExecStop=${BIN_PATH} save

[Install]
WantedBy=multi-user.target
EOF

# 4. Set correct file permissions
echo "--> Setting permissions..."
chmod 755 "$BIN_PATH"
chmod 755 "$BACKUP_SCRIPT_PATH"
chmod 755 "$UNINSTALL_SCRIPT_PATH"
chmod 644 "$CONFIG_PATH"
chmod 644 "$SERVICE_PATH"

# 5. Auto-configure Docker Desktop user in the *installed* config file
if [[ -n "$SUDO_USER" ]] && [[ "$SUDO_USER" != "root" ]]; then
    echo "--> Detected sudo user '$SUDO_USER'. Configuring for Docker Desktop."
    sed -i "s/DOCKER_DESKTOP_USER=\".*\"/DOCKER_DESKTOP_USER=\"$SUDO_USER\"/" "$CONFIG_PATH"
else
    echo "--> No sudo user detected. Clearing Docker Desktop user setting."
    sed -i "s/DOCKER_DESKTOP_USER=\".*\"/DOCKER_DESKTOP_USER=\"\"/" "$CONFIG_PATH"
fi

# 6. Reload systemd daemon and enable the new service
echo "--> Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

echo ""
echo ">>> Installation complete."
echo "The '$SERVICE_NAME' service is now enabled."
echo "An uninstaller has been placed at: $UNINSTALL_SCRIPT_PATH"
echo ""
echo "--- Next Steps: Automated Backups ---"
echo "To enable automated backups, you must set up a cron job."
echo "1. Edit the root crontab: sudo crontab -e"
echo "2. Add a line to schedule the backup script. For example, to run daily at 3 AM:"
echo "   0 3 * * * $BACKUP_SCRIPT_PATH"
echo ""
echo "You can view logs with: tail -f $LOG_FILE"
