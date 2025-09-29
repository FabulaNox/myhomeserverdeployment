# Ensure restore_from_json.sh is installed and executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTORE_JSON_SCRIPT="$SCRIPT_DIR/restore_from_json.sh"
if [ -f "$RESTORE_JSON_SCRIPT" ]; then
    chmod +x "$RESTORE_JSON_SCRIPT"
    cp -f "$RESTORE_JSON_SCRIPT" /usr/local/bin/restore_from_json.sh
    chmod +x /usr/local/bin/restore_from_json.sh
    echo "[deploy] Installed restore_from_json.sh to /usr/local/bin."
else
    echo "[deploy] WARNING: restore_from_json.sh not found in $SCRIPT_DIR."
fi
# --- Create docker-restore-onboot systemd service dynamically ---
# --- Load config early for all path variables ---
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
# Path to docker-restore CLI
DOCKER_RESTORE_BIN="/usr/local/bin/docker-restore"
# Path to onboot systemd unit
ONBOOT_SERVICE="/etc/systemd/system/docker-restore-onboot.service"
EOF
    echo "[INFO] Default config created at $CONFIG_FILE."
fi
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi

# --- Create docker-restore-onboot systemd service dynamically using config vars ---
sudo tee "$ONBOOT_SERVICE" > /dev/null <<EOF
[Unit]
Description=Restore Docker containers from backup on boot
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$DOCKER_RESTORE_BIN -run-restore
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable $(basename "$ONBOOT_SERVICE")
echo "[INFO] docker-restore-onboot.service created and enabled."
# --- Automatically enable Docker API over TCP (for fallback) ---
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
BACKUP_RESTORE_SCRIPT_LOCAL="$SCRIPT_SRC/docker_backup_restore.sh"
if [ -f "$BACKUP_RESTORE_SCRIPT_LOCAL" ]; then
    if [ -L "$DOCKER_RESTORE_BIN" ] || [ -e "$DOCKER_RESTORE_BIN" ]; then
        rm -f "$DOCKER_RESTORE_BIN"
    fi
    ln -s "$BACKUP_RESTORE_SCRIPT_LOCAL" "$DOCKER_RESTORE_BIN"
    echo "[INFO] Symlinked $BACKUP_RESTORE_SCRIPT_LOCAL as $DOCKER_RESTORE_BIN (for docker-restore CLI)"
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

# --- Create main docker-autostart systemd service dynamically using config vars ---
if [ ! -f "$SYSTEMD_SERVICE" ]; then
    echo "[INFO] Systemd service file not found. Creating $SYSTEMD_SERVICE."
    sudo tee "$SYSTEMD_SERVICE" > /dev/null <<EOF
[Unit]
Description=Docker Autostart - Save and restore running containers
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash $BIN_PATH
ExecStop=/bin/bash $BACKUP_SCRIPT_DST
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi
sudo sed -i "s|ExecStart=.*|ExecStart=/bin/bash $BIN_PATH|" "$SYSTEMD_SERVICE"
echo "[INFO] Reloading systemd daemon..."
sudo systemctl daemon-reload
sudo systemctl enable $(basename "$SYSTEMD_SERVICE")
sudo systemctl restart $(basename "$SYSTEMD_SERVICE")
echo "[INFO] Systemd service restarted."

echo "[SUCCESS] Deployment complete."
