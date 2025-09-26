#!/bin/bash
# Automated cleanup for docker-autostart service and related files
# Usage: sudo exit docker_autostart

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

# Stop the systemd service
systemctl stop docker-autostart.service

# Remove all files in $AUTOSCRIPT_DIR (except config)
sudo rm -f "$AUTOSCRIPT_DIR"/*.log "$AUTOSCRIPT_DIR"/*.lock "$CONTAINER_LIST" "$AUTOSCRIPT_DIR"/dropped_containers.txt

# Optionally remove test containers (uncomment if desired)
# docker rm -f test_autostart_container

# Confirm cleanup
ls -l "$AUTOSCRIPT_DIR"

echo "[SUCCESS] docker-autostart.service stopped and all related files cleaned up."

