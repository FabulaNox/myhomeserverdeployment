#!/bin/bash
# enable_docker_tcp.sh: Enable Docker API over TCP (insecure, for local use only)
# Usage: sudo bash enable_docker_tcp.sh

set -e

DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_JSON="/etc/docker/daemon.json.bak.$(date +%s)"

# Backup existing config
if [ -f "$DAEMON_JSON" ]; then
    cp "$DAEMON_JSON" "$BACKUP_JSON"
    echo "[INFO] Backed up $DAEMON_JSON to $BACKUP_JSON"
fi

# Patch or create daemon.json
if grep -q 'tcp://0.0.0.0:2375' "$DAEMON_JSON" 2>/dev/null || grep -q 'tcp://127.0.0.1:2375' "$DAEMON_JSON" 2>/dev/null; then
    echo "[INFO] TCP already enabled in $DAEMON_JSON"
else
    if [ -f "$DAEMON_JSON" ]; then
        jq '.hosts |= (if . == null then ["unix:///var/run/docker.sock", "tcp://127.0.0.1:2375"] else (. + ["tcp://127.0.0.1:2375"] | unique) end)' "$DAEMON_JSON" > "$DAEMON_JSON.tmp" && mv "$DAEMON_JSON.tmp" "$DAEMON_JSON"
    else
        echo '{"hosts": ["unix:///var/run/docker.sock", "tcp://127.0.0.1:2375"]}' > "$DAEMON_JSON"
    fi
    echo "[INFO] TCP host added to $DAEMON_JSON"
fi

# Restart Docker
echo "[INFO] Restarting Docker service..."
systemctl restart docker
sleep 2
echo "[SUCCESS] Docker API over TCP enabled on 127.0.0.1:2375 (insecure, local only)"
