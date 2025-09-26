#!/bin/bash
# fix_docker_socket.sh: Ensure Docker Desktop socket is accessible to systemd/root
# Usage: sudo bash fix_docker_socket.sh

set -e


# Source config for all paths
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi

# Default Desktop socket path (update if different)
DESKTOP_SOCKET="/home/bogdan/.docker/desktop/docker.sock"
SYSTEM_SOCKET="/var/run/docker.sock"

if [ ! -S "$DESKTOP_SOCKET" ]; then
    echo "[ERROR] Docker Desktop socket not found at $DESKTOP_SOCKET. Is Docker Desktop running?" >&2
    exit 1
fi

sudo ln -sf "$DESKTOP_SOCKET" "$SYSTEM_SOCKET"
echo "[INFO] Symlinked $DESKTOP_SOCKET to $SYSTEM_SOCKET."

# Optionally restart docker-autostart service
if systemctl is-active --quiet docker-autostart.service; then
    sudo systemctl restart docker-autostart.service
    echo "[INFO] Restarted docker-autostart.service."
else
    echo "[INFO] docker-autostart.service is not active."
fi

echo "[SUCCESS] Docker socket fix applied."

