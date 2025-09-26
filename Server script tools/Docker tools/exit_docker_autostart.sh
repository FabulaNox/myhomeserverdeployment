#!/bin/bash
# Automated cleanup for docker_autostart service and related files
# Usage: sudo exit docker_autostart

set -e

# Stop the systemd service
systemctl stop docker-autostart.service

# Remove all files in /usr/autoscript (except config)
sudo rm -f /usr/autoscript/*.log /usr/autoscript/*.lock /usr/autoscript/running_containers.txt /usr/autoscript/dropped_containers.txt

# Optionally remove test containers (uncomment if desired)
# docker rm -f test_autostart_container

# Confirm cleanup
ls -l /usr/autoscript

echo "[SUCCESS] docker_autostart service stopped and all related files cleaned up."
