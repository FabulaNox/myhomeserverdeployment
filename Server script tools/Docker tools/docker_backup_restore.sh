# --- Full uninstall: remove all traces of deployment ---
full_uninstall() {
    echo "[docker-restore -full-uninstall] Removing all deployment traces..."
    # Remove symlink if exists
    if [ -L /usr/local/bin/docker-restore ]; then
        sudo rm /usr/local/bin/docker-restore && echo "Removed symlink /usr/local/bin/docker-restore"
    fi
    # Remove systemd service files if exist
    if [ -f /etc/systemd/system/docker-autostart.service ]; then
        sudo systemctl stop docker-autostart.service 2>/dev/null
        sudo rm /etc/systemd/system/docker-autostart.service && echo "Removed systemd unit docker-autostart.service"
    fi
    if [ -f /etc/systemd/system/docker-backup-restore@.service ]; then
        sudo systemctl stop docker-backup-restore@.service 2>/dev/null
        sudo rm /etc/systemd/system/docker-backup-restore@.service && echo "Removed systemd unit docker-backup-restore@.service"
    fi
    # Remove autoscript data
    if [ -d /usr/autoscript ]; then
        sudo rm -rf /usr/autoscript && echo "Removed /usr/autoscript directory"
    fi
    # Remove all script files in this directory (use with caution)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "Removing script files in $SCRIPT_DIR..."
    find "$SCRIPT_DIR" -type f -name 'docker_*' -exec rm -f {} +
    echo "[docker-restore -full-uninstall] Uninstall complete."
}

# --- Command-line full uninstall ---
if [[ "$1" == "-full-uninstall" ]]; then
    full_uninstall
    exit 0
fi
    echo "  -full-uninstall           Remove all deployment traces: scripts, symlinks, systemd units, autoscript data (CAUTION: destructive)"
# --- Find next available port ---
find_next_available_port() {
    local start_port="$1"
    local max_port=65535
    local port=$start_port
    while [ $port -le $max_port ]; do
        if ! ss -tuln | grep -q ":$port[[:space:]]" && ! docker ps --format '{{.Ports}}' | grep -q ":$port->"; then
            echo $port
            return
        fi
        port=$((port+1))
    done
    echo "0" # No available port found
}
# --- Clean Docker field: stop/remove all containers, prune networks/volumes ---
clean_docker_field() {
    echo "[docker-restore -clean-field] Stopping all containers..."
    all_containers=$(docker ps -aq)
    if [ -n "$all_containers" ]; then
        docker stop $all_containers || true
        # Disable restart policy for all containers before removal
        for cid in $all_containers; do
            docker update --restart=no "$cid" || true
        done
        echo "[docker-restore -clean-field] Removing all containers (with restart policy disabled)..."
        docker rm -f $all_containers || true
    else
        echo "[docker-restore -clean-field] No containers to stop/remove."
    fi
    echo "[docker-restore -clean-field] Pruning unused networks..."
    docker network prune -f
    echo "[docker-restore -clean-field] Pruning unused volumes..."
    docker volume prune -f
    echo "[docker-restore -clean-field] Docker field cleaned."
}

# --- Command-line clean field ---
if [[ "$1" == "-clean-field" ]]; then
    clean_docker_field
    exit 0
fi
############################################################
# USAGE NOTE:
#
# Due to spaces in the script path, always invoke this script as:
#   sudo bash 'Server script tools/Docker tools/docker_backup_restore.sh' <command>
# Or create a symlink or wrapper script in a path without spaces for easier use.
#
# Example wrapper (recommended, run once):
#   sudo ln -s "$(pwd)/Server script tools/Docker tools/docker_backup_restore.sh" /usr/local/bin/docker-restore
# Then use:
#   sudo docker-restore <command>
#
# All commands require sudo/root privileges.
############################################################
# --- Usage/help function ---
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -run-restore              Run the restore process (requires stopped autostart service)"
    echo "  -m-restore                Manual restore preview (dry run, no changes)"
    echo "  -image-capture-no-run     Capture backup image (no restore)"
    echo "  -stop-autostart           Stop the docker-autostart service"
    echo "  -resume-autostart         Resume the docker-autostart service"
    echo "  -restart-container <name> Restart a specific container by name or ID"
    echo "  -restart-all              Restart all stopped containers"
    echo "  -h, --help                Show this help message"
    exit 1
}

# --- Restart a specific container ---
restart_container() {
    local cname="$1"
    if [ -z "$cname" ]; then
        echo "Error: Container name or ID required for -restart-container"
        exit 1
    fi
    echo "Restarting container: $cname"
    docker restart "$cname"
    if [ $? -eq 0 ]; then
        echo "Container $cname restarted successfully."
    else
        echo "Failed to restart container $cname."
        exit 1
    fi
}

# --- Restart all stopped containers ---
restart_all_containers() {
    echo "Restarting all stopped containers..."
    local stopped_ids
    stopped_ids=$(docker ps -a -q -f status=exited)
    if [ -z "$stopped_ids" ]; then
        echo "No stopped containers to restart."
        return
    fi
    for cid in $stopped_ids; do
        docker restart "$cid"
        if [ $? -eq 0 ]; then
            echo "Container $cid restarted."
        else
            echo "Failed to restart container $cid."
        fi
    done
    echo "All stopped containers processed."
}

# --- Command-line argument parsing ---
if [[ "$1" == "-restart-container" ]]; then
    shift
    restart_container "$1"
    exit 0
fi

if [[ "$1" == "-restart-all" ]]; then
    restart_all_containers
    exit 0
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi
#!/bin/bash
# docker_backup_restore.sh: Dedicated backup/restore handler for containers
# Usage: sudo ./docker_backup_restore.sh -run-restore | -m-restore | -image-capture-no-run | ...

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi

# Use a separate lockfile for backup/restore
BACKUP_LOCKFILE="${AUTOSCRIPT_DIR}/backup_restore.lock"
acquire_backup_lock() {
    exec 9>"$BACKUP_LOCKFILE"
    flock -n 9 || { echo "[ERROR] Another backup/restore is running."; exit 1; }
}
release_backup_lock() {
    flock -u 9
    rm -f "$BACKUP_LOCKFILE"
}

acquire_backup_lock
trap release_backup_lock EXIT

# --- Command-line run restore (actually start containers) ---
if [[ "$1" == "-run-restore" ]]; then
    echo "[docker-restore -run-restore] Cleaning Docker field before restore..."
    clean_docker_field
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    if [ ! -f "$JSON_BACKUP_FILE" ]; then
        echo "[docker-restore -run-restore] No backup file found at $JSON_BACKUP_FILE" >&2
        exit 1
    fi
    count=$(jq length "$JSON_BACKUP_FILE")
    echo "[docker-restore -run-restore] Restoring $count containers/images from backup..."
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].ContainerName" "$JSON_BACKUP_FILE")
        image=$(jq -r ".[$idx].Image" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus" "$JSON_BACKUP_FILE")
        ports=$(jq -r ".[$idx].Ports | keys[]?" "$JSON_BACKUP_FILE")
        envs=$(jq -r ".[$idx].Env[]?" "$JSON_BACKUP_FILE")
        # Remove existing container if present
        if docker ps -a --format '{{.Names}}' | grep -q "^$name$"; then
            echo "[docker-restore -run-restore] Removing existing container $name..."
            docker rm -f "$name"
        fi
        args=(run -d --name "$name")
        for port in $ports; do
            host_port=$(jq -r ".[$idx].Ports[\"$port\"][0].HostPort" "$JSON_BACKUP_FILE")
            if [ -n "$host_port" ]; then
                # Check if port is available
                if ss -tuln | grep -q ":$host_port[[:space:]]" || docker ps --format '{{.Ports}}' | grep -q ":$host_port->"; then
                    echo "[docker-restore] Port $host_port is in use. Searching for next available..."
                    new_port=$(find_next_available_port $((host_port+1)))
                    if [ "$new_port" = "0" ]; then
                        msg="[docker-restore] No available port found for container $name (requested $host_port). Skipping port mapping."
                        echo "$msg"
                        echo "$msg" >> /usr/autoscript/restore_status.log
                    else
                        msg="[docker-restore] Reassigning $name port $port to $new_port (was $host_port)"
                        echo "$msg"
                        echo "$msg" >> /usr/autoscript/restore_status.log
                        args+=( -p "$new_port:$port" )
                    fi
                else
                    args+=( -p "$host_port:$port" )
                fi
            fi
        done
        if [ -n "$envs" ]; then
            while IFS= read -r env; do
                if [ -n "$env" ]; then
                    args+=( -e "$env" )
                fi
            done <<< "$envs"
        fi
        if [ -n "$image" ]; then
            args+=( "$image" )
            echo "[docker-restore -run-restore] Running: docker ${args[*]}"
            docker "${args[@]}"
            echo "[OK] $name started from image $image."
        else
            echo "[docker-restore -run-restore] Skipped $name: missing image name."
        fi
    done
    echo "[docker-restore -run-restore] Restore complete."
    exit 0
fi
# Add to usage/help
    echo "  -clean-field              Stop/remove all containers, prune networks/volumes (CAUTION: destructive)"

# --- Command-line image capture and stop (no run) ---
if [[ "$1" == "-image-capture-no-run" ]]; then
    echo "[docker-restore -image-capture-no-run] Backing up and stopping all running containers..."
    # Call the save_containers function (defined below)
    save_containers
    # Now stop all running containers
    running=$(docker ps -q)
    if [ -n "$running" ]; then
        docker stop $running
        echo "[docker-restore -image-capture-no-run] Stopped containers: $running"
    else
        echo "[docker-restore -image-capture-no-run] No running containers to stop."
    fi
    exit 0
fi

# --- Command-line restore preview (dry run) ---
if [[ "$1" == "-m-restore" ]]; then
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    if [ ! -f "$JSON_BACKUP_FILE" ]; then
        echo "[docker-restore -m-restore] No backup file found at $JSON_BACKUP_FILE" >&2
        exit 1
    fi
    count=$(jq length "$JSON_BACKUP_FILE")
    echo "[docker-restore -m-restore] Containers/images to be restored: ($count total)"
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].ContainerName" "$JSON_BACKUP_FILE")
        image=$(jq -r ".[$idx].Image" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus" "$JSON_BACKUP_FILE")
        echo "[$((idx+1))] $name | Image: $image | LastStatus: $status"
    done
    echo "--- Starting manual restore (dry run, no containers will be started) ---"
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].ContainerName" "$JSON_BACKUP_FILE")
        image=$(jq -r ".[$idx].Image" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus" "$JSON_BACKUP_FILE")
        echo "Restoring: $name (image: $image, last status: $status) ..."
        sleep 1
        echo "[OK] $name ready for restore."
    done
    echo "[docker-restore -m-restore] Restore preview complete."
    exit 0
fi

# --- Stop all running docker_autostart.sh processes ---
stop_autostart_service() {
    echo "[docker-backup-restore] Stopping all running docker_autostart.sh processes..."
    pkill -f /usr/local/bin/docker_autostart.sh && echo "Stopped all docker_autostart.sh processes." || echo "No running docker_autostart.sh processes found."
}

if [[ "$1" == "-stop-autostart" ]]; then
    stop_autostart_service
    exit 0
fi

# --- Resume (start) the docker-autostart service ---
resume_autostart_service() {
    echo "[docker-backup-restore] Starting docker-autostart.service..."
    systemctl start docker-autostart.service && echo "docker-autostart.service started." || echo "Failed to start docker-autostart.service."
}

if [[ "$1" == "-resume-autostart" ]]; then
    resume_autostart_service
    exit 0
fi

# --- Save containers function (for backup) ---
save_containers() {
    IMAGE_BACKUP_DIR="$AUTOSCRIPT_DIR/image_backups"
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    mkdir -p "$IMAGE_BACKUP_DIR" "$CONFIG_BACKUP_DIR"
    docker ps -q > "$CONTAINER_LIST"
    echo '[' > "$JSON_BACKUP_FILE"
    first=1
    for container in $(docker ps -q); do
        if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
            details=$(docker inspect "$container")
            if [ $first -eq 0 ]; then
                echo ',' >> "$JSON_BACKUP_FILE"
            fi
            echo "$details" | jq '.[0]' >> "$JSON_BACKUP_FILE"
            first=0
            image=$(docker inspect --format='{{.Config.Image}}' "$container")
            name=$(docker inspect --format='{{.Name}}' "$container" | sed 's/\///')
            if [ -n "$image" ]; then
                backup_file="$IMAGE_BACKUP_DIR/${name}_${container}.tar"
                docker save "$image" -o "$backup_file"
                echo "[$(date)] Saved image $image for container $name ($container) to $backup_file"
            fi
        fi
    done
    echo ']' >> "$JSON_BACKUP_FILE"
}
