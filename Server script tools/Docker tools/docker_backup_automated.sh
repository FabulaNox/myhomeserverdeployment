#!/bin/bash
# Unified Docker backup for CLI and Desktop
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    export DOCKER_HOST
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$AUTOSCRIPT_DIR" "$IMAGE_BACKUP_DIR" "$CONFIG_BACKUP_DIR"

# Gather all containers (CLI + Desktop)
containers=$(docker ps -a -q)
echo '[' > "$JSON_BACKUP_FILE"
first=1
for container in $containers; do
    name=$(docker inspect --format='{{.Name}}' "$container" 2>>"$ERROR_LOG" | sed 's/\///')
    ports=$(docker inspect "$container" 2>>"$ERROR_LOG" | jq '.[0].HostConfig.PortBindings')
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>>"$ERROR_LOG")
    image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>>"$ERROR_LOG")
    envs=$(docker inspect "$container" 2>>"$ERROR_LOG" | jq '.[0].Config.Env')
    entry=$(jq -n --arg name "$name" --argjson ports "$ports" --arg status "$status" --arg image "$image" --argjson envs "$envs" '{ContainerName:$name, Image:$image, Ports:$ports, LastStatus:$status, Env:$envs}')
    if [ $first -eq 0 ]; then
        echo ',' >> "$JSON_BACKUP_FILE"
    fi
    echo "$entry" >> "$JSON_BACKUP_FILE"
    first=0
done
echo ']' >> "$JSON_BACKUP_FILE"
if [ $first -eq 0 ]; then
    echo "[$DATE] Backup successful: $JSON_BACKUP_FILE" >> "$ERROR_LOG"
else
    echo "[$DATE] Backup failed" >> "$ERROR_LOG"
    exit 1
fi
