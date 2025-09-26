#!/bin/bash
# docker_autostart_bootstrap.sh: Ensures docker_autostart prerequisites, restores service, and hands off to main service
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source config for all paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2; exit 2
fi

# Restore containers from config before starting service
restore_containers() {
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    mkdir -p "$CONFIG_BACKUP_DIR"
    for config_file in "$CONFIG_BACKUP_DIR"/*.json; do
        [ -e "$config_file" ] || continue
        container_name=$(jq -r '.[0].Name' "$config_file" | sed 's/^\///')
        image=$(jq -r '.[0].Config.Image' "$config_file")
        if ! docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            args=(run -d --name "$container_name")
            for port in $(jq -r '.[0].HostConfig.PortBindings | keys[]?' "$config_file"); do
                host_port=$(jq -r ".[0].HostConfig.PortBindings[\"$port\"][0].HostPort" "$config_file")
                if [ -n "$host_port" ]; then
                    echo "[DEBUG] Adding port mapping: $host_port:$port" >> "$ERROR_LOG"
                    args+=( -p "$host_port:$port" )
                fi
            done
            if [ -n "$image" ]; then
                args+=( "$image" )
                echo "[DEBUG] Final docker command: docker ${args[@]}" >> "$ERROR_LOG"
                for idx in "${!args[@]}"; do
                    echo "[DEBUG] args[$idx]: '${args[$idx]}'" >> "$ERROR_LOG"
                done
                docker "${args[@]}" 2>>"$ERROR_LOG"
            else
                echo "[$(date)] Skipped container $container_name: missing image name" >> "$ERROR_LOG"
            fi
        else
            docker start "$container_name" 2>>"$ERROR_LOG"
        fi
    done
}

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOSTART_SCRIPT="$SCRIPT_DIR/docker_autostart.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_docker_autostart.sh"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
LOCKFILE_SCRIPT="$SCRIPT_DIR/lockfile.sh"
SERVICE_FILE="/etc/systemd/system/docker-autostart.service"

# Ensure root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Exiting." >&2
    exit 10
fi

# Prepare prerequisites
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file missing: $CONFIG_FILE. Run deployment script." >&2
    if [ -x "$DEPLOY_SCRIPT" ]; then
        bash "$DEPLOY_SCRIPT"
    else
        exit 2
    fi
fi
if [ ! -f "$LOCKFILE_SCRIPT" ]; then
    echo "[ERROR] Lockfile script missing: $LOCKFILE_SCRIPT. Run deployment script." >&2
    if [ -x "$DEPLOY_SCRIPT" ]; then
        bash "$DEPLOY_SCRIPT"
    else
        exit 2
    fi
fi
if [ ! -f "$AUTOSTART_SCRIPT" ]; then
    echo "[ERROR] Main script missing: $AUTOSTART_SCRIPT. Run deployment script." >&2
    if [ -x "$DEPLOY_SCRIPT" ]; then
        bash "$DEPLOY_SCRIPT"
    else
        exit 2
    fi
fi


# Ensure the bootstrap systemd unit file exists and is correct
BOOTSTRAP_UNIT_FILE="/etc/systemd/system/docker_autostart_bootstrap.service"
if [ ! -f "$BOOTSTRAP_UNIT_FILE" ]; then
    cat <<EOF > "$BOOTSTRAP_UNIT_FILE"
[Unit]
Description=Bootstrap docker_autostart at boot
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/docker_autostart_bootstrap.sh
RemainAfterExit=true
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

# Restore main service file if missing
if [ ! -f "$SERVICE_FILE" ]; then
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Docker Autostart - Save and restore running containers
Requires=docker.service

[Service]
ExecStart=$AUTOSTART_SCRIPT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

# Reload and enable both services
systemctl daemon-reload
systemctl enable docker_autostart_bootstrap.service
systemctl enable docker-autostart.service

# Restore containers before starting main service
restore_containers
systemctl start docker-autostart.service

sleep 2

STATUS=$(systemctl is-active docker-autostart.service)
if [ "$STATUS" = "active" ]; then
    echo "[SUCCESS] docker-autostart.service is running."
    exit 0
else
    echo "[ERROR] docker-autostart.service failed to start. Check logs."
    systemctl status docker-autostart.service --no-pager
    exit 1
fi
