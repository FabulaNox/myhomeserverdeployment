# --- Automatically enable Docker API over TCP (for fallback) ---
ENABLE_TCP_SCRIPT="$SCRIPT_SRC/enable_docker_tcp.sh"
if [ -x "$ENABLE_TCP_SCRIPT" ]; then
    echo "[INFO] Running Docker TCP API enable script..."
    sudo bash "$ENABLE_TCP_SCRIPT"
else
    echo "[WARNING] Docker TCP API enable script not found or not executable: $ENABLE_TCP_SCRIPT"
fi
#!/bin/bash
# Automated deployment script for docker_autostart.sh and related files
# Usage: sudo ./deploy_docker_autostart.sh


set -e

# Ensure SCRIPT_SRC is set to the directory of this script
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# --- Restore missing .sh files from Docker interface directory ---
INTERFACE_DIR="$(dirname "$SCRIPT_SRC")/Docker interface"
restore_from_interface() {
    local fname="$1"
    if [ ! -f "$SCRIPT_SRC/$fname" ] && [ -f "$INTERFACE_DIR/$fname" ]; then
        echo "[INFO] Restoring $fname from $INTERFACE_DIR."
        cp "$INTERFACE_DIR/$fname" "$SCRIPT_SRC/$fname"
        chmod +x "$SCRIPT_SRC/$fname"
    fi
}
restore_from_interface "docker_autostart.sh"
restore_from_interface "docker_backup_automated.sh"
restore_from_interface "docker_autostart_bootstrap.sh"
restore_from_interface "exit_docker_autostart.sh"
restore_from_interface "fix_docker_socket.sh"

# --- Automatically apply Docker socket fix ---
SOCKET_FIX_SCRIPT="$SCRIPT_SRC/fix_docker_socket.sh"
if [ -x "$SOCKET_FIX_SCRIPT" ]; then
    echo "[INFO] Running Docker socket fix script..."
    sudo bash "$SOCKET_FIX_SCRIPT"
else
    echo "[WARNING] Docker socket fix script not found or not executable: $SOCKET_FIX_SCRIPT"
fi
restore_from_interface "lockfile.sh"

CONFIG_FILE="$SCRIPT_SRC/docker_autostart.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[INFO] Config file not found: $CONFIG_FILE. Creating with defaults."
    cat > "$CONFIG_FILE" <<EOF
# Docker host socket (for CLI and Desktop compatibility)
DOCKER_HOST="unix:///var/run/docker.sock"
# Path to systemd service file (for bootstrap)
SERVICE_FILE="/etc/systemd/system/docker-autostart.service"
# Directory for all script data/logs/lockfiles
AUTOSCRIPT_DIR="/usr/autoscript"
# List of running containers (updated by script)
CONTAINER_LIST="\$AUTOSCRIPT_DIR/running_containers.txt"
# Error log file
ERROR_LOG="\$AUTOSCRIPT_DIR/error.log"
# Health log file
HEALTH_LOG="\$AUTOSCRIPT_DIR/container_health.log"
# Lockfile for duplicate prevention
LOCKFILE="\$AUTOSCRIPT_DIR/docker_autostart.lock"
# Image backup directory
IMAGE_BACKUP_DIR="\$AUTOSCRIPT_DIR/image_backups"
# Container config backup directory
CONFIG_BACKUP_DIR="\$AUTOSCRIPT_DIR/container_configs"
# Unified JSON backup file
JSON_BACKUP_FILE="\$AUTOSCRIPT_DIR/container_details.json"
# Restore status log file
RESTORE_LOG="\$AUTOSCRIPT_DIR/restore_status.log"
# Systemd service file path
SYSTEMD_SERVICE="/etc/systemd/system/docker-autostart.service"
# Path to main script (must match systemd ExecStart)
BIN_PATH="/usr/local/bin/docker_autostart.sh"
# Path to lockfile script
LOCKFILE_SCRIPT="/usr/local/bin/lockfile.sh"
# Path to deploy script
DEPLOY_SCRIPT="/usr/local/bin/deploy_docker_autostart.sh"
# Path to main autostart script (for bootstrap)
AUTOSTART_SCRIPT="/usr/local/bin/docker_autostart.sh"
EOF
    echo "[INFO] Default config created at $CONFIG_FILE."
fi

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
if [ -f "$BACKUP_SCRIPT_SRC" ]; then
    install -m 700 "$BACKUP_SCRIPT_SRC" "$BACKUP_SCRIPT_DST"
    echo "[INFO] Backup script copied to $BACKUP_SCRIPT_DST"
else
    echo "[WARNING] Backup script not found at $BACKUP_SCRIPT_SRC, skipping."
fi


# 1b. Symlink docker_backup_restore.sh as docker-restore for CLI backup/restore commands
RESTORE_LINK="$BIN_DIR/docker-restore"
BACKUP_RESTORE_SCRIPT_LOCAL="$SCRIPT_SRC/docker_backup_restore.sh"
if [ -f "$BACKUP_RESTORE_SCRIPT_LOCAL" ]; then
    if [ -L "$RESTORE_LINK" ] || [ -e "$RESTORE_LINK" ]; then
        rm -f "$RESTORE_LINK"
    fi
    ln -s "$BACKUP_RESTORE_SCRIPT_LOCAL" "$RESTORE_LINK"
    echo "[INFO] Symlinked $BACKUP_RESTORE_SCRIPT_LOCAL as $RESTORE_LINK (for docker-restore CLI)"
else
    echo "[WARNING] docker_backup_restore.sh not found in $SCRIPT_SRC, docker-restore CLI will not be available."
fi


# 2. Ensure all referenced directories exist and are writable
mkdir -p "$AUTOSCRIPT_DIR"
chmod 770 "$AUTOSCRIPT_DIR"
echo "[INFO] Autoscript directory ensured at $AUTOSCRIPT_DIR"


# 3. Update BIN_PATH in config if script was moved (optional, handled by config)
# (No action needed unless user wants to change BIN_PATH)




# 4. Ensure systemd unit file exists and has correct ExecStart path
if [ ! -f "$SYSTEMD_SERVICE" ]; then
    echo "[INFO] Systemd service file not found. Creating $SYSTEMD_SERVICE."
    cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Docker Autostart - Save and restore running containers
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/docker_autostart.sh
ExecStop=/bin/bash /usr/local/bin/docker_backup_automated.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi
sed -i 's|ExecStart=.*|ExecStart=/bin/bash /usr/local/bin/docker_autostart.sh|' "$SYSTEMD_SERVICE"
echo "[INFO] Reloading systemd daemon..."
systemctl daemon-reload
systemctl enable docker-autostart.service
systemctl restart docker-autostart.service
echo "[INFO] Systemd service restarted."

echo "[SUCCESS] Deployment complete."
