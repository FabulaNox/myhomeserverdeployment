#!/bin/bash
# Automated deployment script for docker_autostart.sh and related files
# Usage: sudo ./deploy_docker_autostart.sh

set -e


# Source config for all paths
CONFIG_FILE="$SCRIPT_SRC/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi

BIN_DIR="/usr/local/bin"
CONFIG_SRC="$SCRIPT_SRC/docker_autostart.conf"
LOCKFILE_SRC="$SCRIPT_SRC/lockfile.sh"
SCRIPT_SRC_FILE="$SCRIPT_SRC/docker_autostart.sh"
CONFIG_DST="$BIN_DIR/docker_autostart.conf"
LOCKFILE_DST="$BIN_DIR/lockfile.sh"
SCRIPT_DST="$BIN_DIR/docker_autostart.sh"


# 1. Copy config, lockfile, main, and backup script to /usr/local/bin
install -m 644 "$CONFIG_SRC" "$CONFIG_DST"
echo "[INFO] Config file copied to $CONFIG_DST"
install -m 644 "$LOCKFILE_SRC" "$LOCKFILE_DST"
echo "[INFO] Lockfile script copied to $LOCKFILE_DST"
install -m 700 "$SCRIPT_SRC_FILE" "$SCRIPT_DST"
echo "[INFO] Main script copied to $SCRIPT_DST"
BACKUP_SCRIPT_SRC="$SCRIPT_SRC/docker_backup_automated.sh"
BACKUP_SCRIPT_DST="$BIN_DIR/docker_backup_automated.sh"
install -m 700 "$BACKUP_SCRIPT_SRC" "$BACKUP_SCRIPT_DST"
echo "[INFO] Backup script copied to $BACKUP_SCRIPT_DST"


# 2. Ensure all referenced directories exist and are writable
mkdir -p "$AUTOSCRIPT_DIR"
chmod 770 "$AUTOSCRIPT_DIR"
echo "[INFO] Autoscript directory ensured at $AUTOSCRIPT_DIR"


# 3. Update BIN_PATH in config if script was moved (optional, handled by config)
# (No action needed unless user wants to change BIN_PATH)


# 4. Ensure systemd unit file has correct ExecStart path
if [ -f "$SYSTEMD_SERVICE" ]; then
    sed -i 's|ExecStart=.*|ExecStart=/bin/bash /usr/local/bin/docker_autostart.sh|' "$SYSTEMD_SERVICE"
    systemctl daemon-reload
    systemctl restart docker-autostart.service
    echo "[INFO] Systemd service restarted."
else
    echo "[INFO] Systemd service file not found. It will be created on first script run."
fi

echo "[SUCCESS] Deployment complete."

