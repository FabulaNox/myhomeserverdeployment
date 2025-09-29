#!/bin/bash

# Config-driven Docker socket fixer
set -e

# Find config file (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ ! -f "$CONF_FILE" ]; then
  echo "[fix-docker-socket] ERROR: Config file not found: $CONF_FILE" >&2
  exit 2
fi
source "$CONF_FILE"

# Allow override from config, else use defaults
SYSTEM_SOCK="${DOCKER_SYSTEM_SOCKET:-/var/run/docker.sock}"
DESKTOP_SOCK="${DOCKER_DESKTOP_SOCKET:-$HOME/.docker/desktop/docker.sock}"

echo "[fix-docker-socket] Using config: SYSTEM_SOCK=$SYSTEM_SOCK, DESKTOP_SOCK=$DESKTOP_SOCK"

# Try Desktop socket first (most common for Docker Desktop)
if [ -S "$DESKTOP_SOCK" ]; then
    sudo ln -sf "$DESKTOP_SOCK" "$SYSTEM_SOCK"
    echo "[fix-docker-socket] Symlinked $DESKTOP_SOCK to $SYSTEM_SOCK."
    exit 0
fi

# If Desktop socket not found, try to restore native Docker socket
if [ -L "$SYSTEM_SOCK" ] && [ ! -e "$SYSTEM_SOCK" ]; then
    sudo rm -f "$SYSTEM_SOCK"
fi
sudo systemctl restart docker.socket || true
sudo systemctl restart docker || true
if [ -S "$SYSTEM_SOCK" ]; then
    echo "[fix-docker-socket] Native Docker socket is available at $SYSTEM_SOCK."
    exit 0
else
    echo "[fix-docker-socket] ERROR: No working Docker socket found at $SYSTEM_SOCK." >&2
    exit 1
fi
