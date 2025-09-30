# --- Command-line restore from JSON directly ---
if [[ "$1" == "-json-now" ]]; then
    RESTORE_JSON_SCRIPT="/usr/local/bin/restore_from_json.sh"
    if [ -x "$RESTORE_JSON_SCRIPT" ]; then
        echo "[docker-restore -json-now] Running restore_from_json.sh..."
        sudo "$RESTORE_JSON_SCRIPT"
    else
        echo "[docker-restore -json-now] ERROR: $RESTORE_JSON_SCRIPT not found or not executable." >&2
        exit 1
    fi
    exit 0
fi

#!/bin/bash
# Force Bash even if invoked with sh or via sudo
[ -z "$BASH_VERSION" ] && exec /bin/bash "$0" "$@"

# --- Docker context detection for Desktop/Root compatibility with TCP fallback ---
# If running as root but Docker Desktop is running as user, use user's Docker context
# If socket fix fails or no containers found, try Docker API over TCP (localhost:2375)
detect_docker_context() {


    # If DOCKER_HOST is set, use it
    if [ -n "$DOCKER_HOST" ]; then
        export DOCKER_HOST
        return
    fi

    # If DOCKER_CONTEXT is set or active, extract the actual socket path and set DOCKER_HOST
    ACTIVE_CONTEXT=$(docker context show 2>/dev/null)
    if [ -n "$ACTIVE_CONTEXT" ]; then
        CONTEXT_HOST=$(docker context inspect "$ACTIVE_CONTEXT" 2>/dev/null | jq -r '.[0].Endpoints.docker.Host // empty')
        if [ -n "$CONTEXT_HOST" ] && [ "$CONTEXT_HOST" != "null" ]; then
            export DOCKER_HOST="$CONTEXT_HOST"
            echo "[docker-restore] Using Docker CLI context: $ACTIVE_CONTEXT (DOCKER_HOST=$DOCKER_HOST)"
            # If context is desktop-linux, require the socket to be accessible
            if [ "$ACTIVE_CONTEXT" = "desktop-linux" ]; then
                # Only proceed if the socket is accessible
                SOCKET_PATH="${CONTEXT_HOST#unix://}"
                if [ ! -S "$SOCKET_PATH" ]; then
                    echo "[docker-restore] ERROR: Docker Desktop socket ($SOCKET_PATH) is not accessible. Cannot proceed with backup/restore for desktop-linux context." >&2
                    exit 3
                fi
            fi
            return
        else
            echo "[docker-restore] Using Docker CLI context: $ACTIVE_CONTEXT (no Host found)"
        fi
    fi
    # Try to detect Docker Desktop socket for user
    if [ -S "/var/run/docker.sock" ]; then
        export DOCKER_HOST="unix:///var/run/docker.sock"
        return
    fi
    # Try common Docker Desktop socket for user
    if [ -n "$SUDO_USER" ]; then
        USER_DOCKER_SOCK="/run/user/$(id -u $SUDO_USER)/docker.sock"
        if [ -S "$USER_DOCKER_SOCK" ]; then
            export DOCKER_HOST="unix://$USER_DOCKER_SOCK"
            return
        fi
    fi
    # Fallback: no special context
    unset DOCKER_HOST
}

detect_docker_context

# --- TCP fallback for Docker API ---
docker_ps_with_fallback() {
    local result
    result=$(docker ps -q)
    if [ -z "$result" ]; then
        # Try TCP fallback if enabled
        export DOCKER_HOST="tcp://localhost:2375"
        result=$(docker ps -q 2>/dev/null)
        if [ -n "$result" ]; then
            echo "[docker-restore] Fallback to Docker API over TCP (localhost:2375) succeeded." >&2
        else
            echo "[docker-restore] No containers found via socket or TCP. Is Docker running and API enabled?" >&2
        fi
    fi
    echo "$result"
}

# --- How to enable Docker API over TCP (for Desktop) ---
# To enable Docker API over TCP (insecure, for local use only!):
#   1. Edit or create ~/.docker/daemon.json and add:
#        { "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"] }
#   2. Restart Docker Desktop.
#   3. Ensure firewall blocks port 2375 from outside localhost.
#   4. Use only on trusted machines.
# Ensure config is sourced from the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 2
fi

# --- Save containers function (for backup, atomic write) ---
save_containers() {
    IMAGE_BACKUP_DIR="$AUTOSCRIPT_DIR/image_backups"
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    TMP_JSON_FILE="${JSON_BACKUP_FILE}.tmp.$$"
    SOCKET_FIX_SCRIPT="$SCRIPT_DIR/fix_docker_socket.sh"
    mkdir -p "$IMAGE_BACKUP_DIR" "$CONFIG_BACKUP_DIR"

    try_save() {
        local containers_list
        containers_list=$(docker_ps_with_fallback)
        if [ -z "$containers_list" ]; then
            return 1
        fi
        echo '[' > "$TMP_JSON_FILE"
        first=1
        for container in $containers_list; do
            if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
                # Get details and extract name, id, and port dependencies
                details=$(docker inspect "$container")
                name=$(echo "$details" | jq -r '.[0].Name' | sed 's#^/##')
                id=$(echo "$details" | jq -r '.[0].Id')
                image=$(echo "$details" | jq -r '.[0].Config.Image')
                # Collect port dependencies as an array of objects {container_port, host_port, protocol}
                ports=$(echo "$details" | jq -c '.[0].NetworkSettings.Ports | to_entries | map(select(.value != null) | {container_port: .key, host_port: .value[0].HostPort, protocol: (.key | split("/")[1])})')
                # Write a custom JSON object for each container
                if [ $first -eq 0 ]; then
                    echo ',' >> "$TMP_JSON_FILE"
                fi
                jq -n --arg name "$name" --arg id "$id" --arg image "$image" --argjson ports "$ports" '{ContainerName: $name, Id: $id, Image: $image, PortDependencies: $ports}' >> "$TMP_JSON_FILE"
                first=0
                if [ -n "$image" ]; then
                    backup_file="$IMAGE_BACKUP_DIR/${name}_${container}.tar"
                    docker save "$image" -o "$backup_file"
                    echo "[$(date)] Saved image $image for container $name ($container) to $backup_file"
                fi
            fi
        done
        echo ']' >> "$TMP_JSON_FILE"
        # Validate JSON before moving
        if jq . "$TMP_JSON_FILE" > /dev/null 2>&1; then
            mv "$TMP_JSON_FILE" "$JSON_BACKUP_FILE"
            echo "[docker-restore] Backup JSON written atomically."
            return 0
        else
            echo "[docker-restore] ERROR: Backup JSON invalid, not saving corrupted file." >&2
            rm -f "$TMP_JSON_FILE"
            return 2
        fi
    }

    # First attempt
    if try_save; then
        return 0
    fi

    # If failed, try to fix the socket and retry silently
    if [ -x "$SOCKET_FIX_SCRIPT" ]; then
        "$SOCKET_FIX_SCRIPT" >/dev/null 2>&1 || true
        if try_save; then
            return 0
        fi
    fi

    # If still failed, show error
    echo "[docker-restore] ERROR: Could not save containers after socket fix attempt." >&2
    return 1
}

# --- Show backup containers function ---
show_backup_containers() {
    local json_file="${JSON_BACKUP_FILE:-/usr/autoscript/container_details.json}"
    echo "[show-backup-containers] Containers in backup JSON ($json_file):"
    jq -r '
      .[] | "- " + .Name + " | image: " + .Config.Image +
      (if .NetworkSettings.Ports then
         (" | ports: " + ( [ (.NetworkSettings.Ports | to_entries[] | (.value[0].HostPort + ":" + .key) ) ] | join(", ") ) )
       else "" end)
    ' "$json_file"
    echo
    local log_file="${RESTORE_LOG:-/usr/autoscript/restore_status.log}"
    if [ -f "$log_file" ]; then
        echo "[show-backup-containers] Recent restore log entries ($log_file):"
        grep -E '\[docker-restore\]|\[OK\]|Reassigning' "$log_file" | tail -20
    else
        echo "[show-backup-containers] No restore log found at $log_file"
    fi
}

# --- Command-line show backup containers ---
if [[ "$1" == "-show-backup-containers" ]]; then

    show_backup_containers
    exit 0
fi
    echo "  -show-backup-containers   Show containers saved in backup JSON and recent restore log"
# --- Full uninstall: remove all traces of deployment ---
full_uninstall() {
    echo "[docker-restore -full-uninstall] Removing all deployment traces (except source .sh files)..."
    # Remove symlink if exists
    if [ -L "$DOCKER_RESTORE_BIN" ]; then
        sudo rm "$DOCKER_RESTORE_BIN" && echo "Removed symlink $DOCKER_RESTORE_BIN"
    fi
    # Remove systemd service files if exist
    if [ -f "$SYSTEMD_SERVICE" ]; then
        sudo systemctl stop $(basename "$SYSTEMD_SERVICE") 2>/dev/null
        sudo rm "$SYSTEMD_SERVICE" && echo "Removed systemd unit $SYSTEMD_SERVICE"
    fi
    if [ -f "$ONBOOT_SERVICE" ]; then
        sudo systemctl stop $(basename "$ONBOOT_SERVICE") 2>/dev/null
        sudo rm "$ONBOOT_SERVICE" && echo "Removed systemd unit $ONBOOT_SERVICE"
    fi
    # Remove autoscript data
    if [ -d "$AUTOSCRIPT_DIR" ]; then
        sudo rm -rf "$AUTOSCRIPT_DIR" && echo "Removed $AUTOSCRIPT_DIR directory"
    fi
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
#   sudo bash 'Server script tools/Docker tools/docker_backup_restore.sh' <command>``
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
# --- Save containers function (for backup) ---
restart_container() {
    local cname="$1"
    if [ -z "$cname" ]; then
        echo "Error: Container name or ID required for -restart-container"
        exit 1
    fi
    echo "Restarting container: $cname"
    SOCKET_FIX_SCRIPT="$SCRIPT_DIR/fix_docker_socket.sh"
    try_restart() {
        docker restart "$cname" 2>&1
        return $?
    }
    if try_restart | grep -q 'Cannot connect to the Docker daemon'; then
        # Try to fix the socket
        if [ -x "$SOCKET_FIX_SCRIPT" ]; then
            "$SOCKET_FIX_SCRIPT" >/dev/null 2>&1 || true
        fi
        if try_restart | grep -q 'Cannot connect to the Docker daemon'; then
            # Try to start native Docker
            sudo systemctl start docker || true
            if try_restart | grep -q 'Cannot connect to the Docker daemon'; then
                echo "Failed to restart container $cname. Docker daemon not available." >&2
                exit 1
            else
                echo "Container $cname restarted successfully (after starting native Docker)."
            fi
        else
            echo "Container $cname restarted successfully (after socket fix)."
        fi
    else
        echo "Container $cname restarted successfully."
    fi
}

# --- Restart all stopped containers ---
restart_all_containers() {
    echo "Restarting all stopped containers..."
    SOCKET_FIX_SCRIPT="$SCRIPT_DIR/fix_docker_socket.sh"
    try_list_stopped() {
        docker ps -a -q -f status=exited 2>&1
    }
    stopped_ids=$(try_list_stopped)
    if echo "$stopped_ids" | grep -q 'Cannot connect to the Docker daemon'; then
        # Try to fix the socket
        if [ -x "$SOCKET_FIX_SCRIPT" ]; then
            "$SOCKET_FIX_SCRIPT" >/dev/null 2>&1 || true
        fi
        stopped_ids=$(try_list_stopped)
        if echo "$stopped_ids" | grep -q 'Cannot connect to the Docker daemon'; then
            # Try to start native Docker
            sudo systemctl start docker || true
            stopped_ids=$(try_list_stopped)
            if echo "$stopped_ids" | grep -q 'Cannot connect to the Docker daemon'; then
                # Final fallback: try restore_from_json.sh
                RESTORE_JSON_SCRIPT="$SCRIPT_DIR/restore_from_json.sh"
                if [ -x "$RESTORE_JSON_SCRIPT" ]; then
                    echo "[docker-restore] All restart attempts failed. Attempting full restore from backup JSON..."
                    sudo "$RESTORE_JSON_SCRIPT"
                else
                    echo "No stopped containers to restart. Docker daemon not available, and restore_from_json.sh not found or not executable." >&2
                fi
                return
            fi
        fi
    fi
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
# Remove stale lockfile if not held by any process
if [ -f "$BACKUP_LOCKFILE" ]; then
    lsof "$BACKUP_LOCKFILE" >/dev/null 2>&1 || rm -f "$BACKUP_LOCKFILE"
fi
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
# --- Transactional restore: rollback on failure ---
if [[ "$1" == "-run-restore" ]]; then
    echo "[docker-restore -run-restore] Cleaning Docker field before restore..."
    clean_docker_field
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    if [ ! -f "$JSON_BACKUP_FILE" ]; then
        echo "[docker-restore -run-restore] No backup file found at $JSON_BACKUP_FILE" >&2
        exit 1
    fi
    # Validate JSON before restore
    if ! jq . "$JSON_BACKUP_FILE" > /dev/null 2>&1; then
        echo "[docker-restore -run-restore] ERROR: Backup JSON is invalid or corrupted. Aborting restore." >&2
        exit 2
    fi
    count=$(jq length "$JSON_BACKUP_FILE")
    echo "[docker-restore -run-restore] Restoring $count containers/images from backup..."
    started_containers=()
    restore_failed=0
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].Name" "$JSON_BACKUP_FILE" | sed 's#^/##')
        image=$(jq -r ".[$idx].Config.Image" "$JSON_BACKUP_FILE")
        ports=$(jq -r ".[$idx].NetworkSettings.Ports | keys[]?" "$JSON_BACKUP_FILE")
        envs=$(jq -r ".[$idx].Config.Env[]?" "$JSON_BACKUP_FILE")
        # Remove existing container if present
        if docker ps -a --format '{{.Names}}' | grep -q "^$name$"; then
            echo "[docker-restore -run-restore] Removing existing container $name..."
            docker rm -f "$name"
        fi
        args=(run -d --name "$name")
        for port in $ports; do
            host_port=$(jq -r ".[$idx].NetworkSettings.Ports[\"$port\"][0].HostPort" "$JSON_BACKUP_FILE")
            container_port=$(echo "$port" | cut -d'/' -f1)
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
                        msg="[docker-restore] Reassigning $name port $container_port to $new_port (was $host_port)"
                        echo "$msg"
                        echo "$msg" >> /usr/autoscript/restore_status.log
                        args+=( -p "$new_port:$container_port" )
                    fi
                else
                    args+=( -p "$host_port:$container_port" )
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
            cid=$(docker "${args[@]}" 2>/dev/null)
            if [ -n "$cid" ]; then
                started_containers+=("$cid")
                echo "[OK] $name started from image $image."
            else
                echo "[ERROR] Failed to start container $name from image $image." >&2
                restore_failed=1
                break
            fi
        else
            echo "[docker-restore -run-restore] Skipped $name: missing image name."
        fi
    done
    if [ $restore_failed -eq 1 ]; then
        echo "[docker-restore -run-restore] ERROR: Restore failed, rolling back started containers..." >&2
        for cid in "${started_containers[@]}"; do
            docker rm -f "$cid" 2>/dev/null || true
        done
        echo "[docker-restore -run-restore] Rollback complete. No containers restored."
        exit 3
    fi
    echo "[docker-restore -run-restore] Restore complete. All containers restored successfully."
    exit 0
fi
# --- System hooks: backup on shutdown, restore on startup ---
# To enable automatic backup on shutdown:
#   sudo ln -s /usr/local/bin/docker-restore /lib/systemd/system-shutdown/docker-backup
# To enable automatic restore on startup:
#   Add a systemd service that runs: sudo docker-restore -run-restore
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
        # Try multiple possible fields for name and image
        name=$(jq -r ".[$idx].ContainerName // .[$idx].Name // null" "$JSON_BACKUP_FILE" | sed 's#^/##')
        image=$(jq -r ".[$idx].Image // .[$idx].Config.Image // null" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus // .[$idx].State.Status // null" "$JSON_BACKUP_FILE")
        echo "[$((idx+1))] $name | Image: $image | LastStatus: $status"
    done
    echo "--- Starting manual restore (dry run, no containers will be started) ---"
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].ContainerName // .[$idx].Name // null" "$JSON_BACKUP_FILE" | sed 's#^/##')
        image=$(jq -r ".[$idx].Image // .[$idx].Config.Image // null" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus // .[$idx].State.Status // null" "$JSON_BACKUP_FILE")
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
