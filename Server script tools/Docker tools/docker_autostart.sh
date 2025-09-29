#!/bin/bash

# --- Command-line restore interface ---
if [[ "$1" == "-image" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
    CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
    if [ -r "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
        exit 2
    fi
    IMAGE_BACKUP_DIR="$AUTOSCRIPT_DIR/image_backups"
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    echo "[docker-restore -image] Listing available images and containers for restore:"
    echo "--- Images in $IMAGE_BACKUP_DIR ---"
    if [ -d "$IMAGE_BACKUP_DIR" ]; then
        ls -1 "$IMAGE_BACKUP_DIR"/*.tar 2>/dev/null || echo "[None found]"
    else
        echo "[None found]"
    fi
    echo "--- Container configs in $CONFIG_BACKUP_DIR ---"
    if [ -d "$CONFIG_BACKUP_DIR" ]; then
        for f in "$CONFIG_BACKUP_DIR"/*.json; do
            [ -e "$f" ] || continue
            cname=$(jq -r '.[0].Name' "$f" | sed 's/^\///')
            img=$(jq -r '.[0].Config.Image' "$f")
            echo "Container: $cname | Image: $img | Config: $f"
        done
    else
        echo "[None found]"
    fi
    exit 0
fi

if [[ "$1" == "-m-restore" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
    CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
    if [ -r "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
        exit 2
    fi
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
# Deployment: Use deploy_docker_autostart.sh for setup (automates copying, permissions, and service restart)
# Stop: sudo systemctl stop docker-autostart.service or pkill -f docker_autostart.sh
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] This script must be run as root. Exiting." >&2
    exit 10
fi

DROPPED_CONTAINERS_LIST="$AUTOSCRIPT_DIR/dropped_containers.txt"
rm -f "$DROPPED_CONTAINERS_LIST"
# Error log open limiter
ERROR_LOG_OPENED=0
open_error_log_once() {
    if [ "$ERROR_LOG_OPENED" -eq 0 ]; then xdg-open "$ERROR_LOG" & ERROR_LOG_OPENED=1; fi
}


# Robust config and lockfile sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
LOCKFILE_SCRIPT="$SCRIPT_DIR/lockfile.sh"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    export DOCKER_HOST
else
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    sleep 10
    exit 2
fi
if [ -r "$LOCKFILE_SCRIPT" ]; then
    . "$LOCKFILE_SCRIPT"
else
    echo "[ERROR] Lockfile script not found: $LOCKFILE_SCRIPT" >&2
    sleep 10
    exit 2
fi

# Trigger automated backup at system start
if [ -x /usr/autoscript/docker_backup_automated.sh ]; then
    /usr/autoscript/docker_backup_automated.sh
fi

# Validate critical variables
if [ -z "$AUTOSCRIPT_DIR" ]; then
    echo "[ERROR] AUTOSCRIPT_DIR is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$CONTAINER_LIST" ]; then
    echo "[ERROR] CONTAINER_LIST variable is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$LOCKFILE" ]; then
    echo "[ERROR] LOCKFILE variable is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$ERROR_LOG" ]; then
    echo "[ERROR] ERROR_LOG variable is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$HEALTH_LOG" ]; then
    echo "[ERROR] HEALTH_LOG variable is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$SYSTEMD_SERVICE" ]; then
    echo "[ERROR] SYSTEMD_SERVICE variable is not set. Check your config file." >&2
    exit 11
fi
if [ -z "$BIN_PATH" ]; then
    echo "[ERROR] BIN_PATH variable is not set. Check your config file." >&2
    exit 11
fi

# Ensure autoscript directory exists after config is sourced
mkdir -p "$AUTOSCRIPT_DIR"
chmod 700 "$AUTOSCRIPT_DIR"

# Ensure container list and health log files exist
touch "$CONTAINER_LIST"
touch "$HEALTH_LOG"
#lockfile path
 # LOCKFILE is sourced from config
#Script start
#identify the script process ID and avoid duplicates

# Check AUTOSCRIPT_DIR is set
clean_old_logs() {
    # Remove logs older than 12 hours (more frequent cleanup)
    find "$ERROR_LOG" "$HEALTH_LOG" -type f -mmin +720 -exec rm -f {} \;
}

# Ensure autoscript directory exists
# Error rate limiting
ERROR_COUNT=0
ERROR_WINDOW_START=$(date +%s)

check_error_rate() {
    local now=$(date +%s)
    # If more than 60 seconds have passed, reset window
    if (( now - ERROR_WINDOW_START > 60 )); then
        ERROR_COUNT=1
        ERROR_WINDOW_START=$now
    else
        ((ERROR_COUNT++))
    fi
    if (( ERROR_COUNT > 5 )); then
        echo "[ERROR] More than 5 errors in 1 minute. Stopping script." | tee -a "$ERROR_LOG"
        exit 3
    fi
}
    #acquire lock, exit if already running
    if ! acquire_lock "$LOCKFILE"; then
        echo "Another instance is already running. Exiting in 10 seconds..." | tee -a "$ERROR_LOG"
        xdg-open "$ERROR_LOG" &
        sleep 10
        exit 1
    fi
#cleanup for lockfile and child processes
cleanup() 
{
    release_lock "$LOCKFILE"
    #kill all child/background jobs spawned by this script
    jobs -p | xargs -r kill
    exit 0
}

#trap exit for cleanup and ensure backup on shutdown
trap 'cleanup; bash "$SCRIPT_DIR/docker_backup_automated.sh"' EXIT SIGTERM SIGINT SIGHUP
# Debug mode: skip persistent loop and background listeners for clean validation
if [ "$DEBUG_MODE" = "1" ]; then
    echo "[DEBUG] Debug mode enabled: skipping event listeners and infinite loop."
    update_c_list
    start_saved_containers
    check_container_health
    echo "[DEBUG] Clean run complete. Exiting."
    exit 0
fi

#container IDs handler variable
c_list="$CONTAINER_LIST"
#function to update the container list txt file
update_c_list() {
    clean_old_logs
    # Retry docker ps up to 5 times if socket error
    local retries=0
    local max_retries=5
    local success=0
    while [ $retries -lt $max_retries ]; do
        docker ps -q > "$CONTAINER_LIST" 2>>"$ERROR_LOG"
        if [ $? -eq 0 ]; then
            success=1
            break
        else
            grep -q "Cannot connect to the Docker daemon" "$ERROR_LOG" && sleep 2
        fi
        retries=$((retries+1))
    done
    if [ $success -eq 0 ]; then
        echo "[$(date)] Error updating container list after $max_retries retries" >> "$ERROR_LOG"
        open_error_log_once
        check_error_rate
    fi
    # Ensure file exists even if no containers
    touch "$CONTAINER_LIST"
}
#function to start saving containers
start_saved_containers() 
{
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    # Restore containers from config if not present
    for config_file in "$CONFIG_BACKUP_DIR"/*.json; do
        [ -e "$config_file" ] || continue
        container_name=$(jq -r '.[0].Name' "$config_file" | sed 's/^\///')
        image=$(jq -r '.[0].Config.Image' "$config_file")
        # Check if container exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            # Clean up any containers using the same ports
            for port in $(jq -r '.[0].HostConfig.PortBindings | keys[]?' "$config_file"); do
                host_port=$(jq -r ".[0].HostConfig.PortBindings[\"$port\"][0].HostPort" "$config_file")
                if [ -n "$host_port" ]; then
                    # Find containers using this port and remove them
                    conflict_containers=$(docker ps -q --filter "publish=$host_port")
                    for c in $conflict_containers; do
                        cname=$(docker inspect --format='{{.Name}}' "$c" | sed 's/^\///')
                        echo "[DEBUG] Removing conflicting container $cname ($c) using port $host_port" >> "$ERROR_LOG"
                        docker rm -f "$c" 2>>"$ERROR_LOG"
                    done
                fi
            done
            # Build docker run args: name, ports, env, image
            args=(run -d --name "$container_name")
            echo "[DEBUG] Config file $config_file contents:" >> "$ERROR_LOG"
            cat "$config_file" >> "$ERROR_LOG"
            for port in $(jq -r '.[0].HostConfig.PortBindings | keys[]?' "$config_file"); do
                host_port=$(jq -r ".[0].HostConfig.PortBindings[\"$port\"][0].HostPort" "$config_file")
                if [ -n "$host_port" ]; then
                    echo "[DEBUG] Adding port mapping: $host_port:$port" >> "$ERROR_LOG"
                    args+=( -p "$host_port:$port" )
                fi
            done
            # Add environment variables if present
            envs=$(jq -r '.[0].Config.Env[]?' "$config_file")
            if [ -n "$envs" ]; then
                while IFS= read -r env; do
                    if [ -n "$env" ]; then
                        args+=( -e "$env" )
                    fi
                done <<< "$envs"
            fi
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
        # After restoration, flush (remove) the config file to avoid stale configs and port conflicts
        rm -f "$config_file"
    done
}
#handle shutdown
save_containers() 
{
    update_c_list
    IMAGE_BACKUP_DIR="$AUTOSCRIPT_DIR/image_backups"
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    JSON_BACKUP_FILE="$AUTOSCRIPT_DIR/container_details.json"
    mkdir -p "$IMAGE_BACKUP_DIR" "$CONFIG_BACKUP_DIR"
    # Persist running container list
    docker ps -q > "$CONTAINER_LIST"
    # Collect all running container details into a single JSON file
    echo '[' > "$JSON_BACKUP_FILE"
    first=1
    for container in $(docker ps -q); do
        if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
            # Get full inspect details
            details=$(docker inspect "$container" 2>>"$ERROR_LOG")
            if [ $first -eq 0 ]; then
                echo ',' >> "$JSON_BACKUP_FILE"
            fi
            echo "$details" | jq '.[0]' >> "$JSON_BACKUP_FILE"
            first=0
            # Save image backup as before
            image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>>"$ERROR_LOG")
            name=$(docker inspect --format='{{.Name}}' "$container" 2>>"$ERROR_LOG" | sed 's/\///')
            if [ -n "$image" ]; then
                backup_file="$IMAGE_BACKUP_DIR/${name}_${container}.tar"
                docker save "$image" -o "$backup_file" 2>>"$ERROR_LOG"
                echo "[$(date)] Saved image $image for container $name ($container) to $backup_file" >> "$HEALTH_LOG"
            fi
        fi
    done
    echo ']' >> "$JSON_BACKUP_FILE"
    exit 0
}
#catch shutdown/restart signal
trap save_containers SIGTERM SIGINT SIGHUP


wait_for_docker() {
    local max_wait=300
    local waited=0
    local interval=5
    while ! docker info >/dev/null 2>&1; do
        echo "[$(date '+%Y-%m-%d_%H-%M-%S')] Waiting for Docker daemon to be available..." | tee -a "$ERROR_LOG"
        sleep $interval
        waited=$((waited+interval))
        if [ $waited -ge $max_wait ]; then
            echo "[$(date '+%Y-%m-%d_%H-%M-%S')] Docker daemon not available after $max_wait seconds. Giving up." | tee -a "$ERROR_LOG"
            return 1
        fi
    done
    echo "[$(date '+%Y-%m-%d_%H-%M-%S')] Docker daemon is active." | tee -a "$ERROR_LOG"
    return 0
}

# Restore containers from unified JSON backup (only those last known as running)
if [ -f "$JSON_BACKUP_FILE" ]; then
    wait_for_docker || exit 4
    loaded=()
    not_loaded=()
    count=$(jq length "$JSON_BACKUP_FILE")
    for idx in $(seq 0 $((count-1))); do
        name=$(jq -r ".[$idx].ContainerName" "$JSON_BACKUP_FILE")
        image=$(jq -r ".[$idx].Image" "$JSON_BACKUP_FILE")
        status=$(jq -r ".[$idx].LastStatus" "$JSON_BACKUP_FILE")
        ports=$(jq -r ".[$idx].Ports | keys[]?" "$JSON_BACKUP_FILE")
        envs=$(jq -r ".[$idx].Env[]?" "$JSON_BACKUP_FILE")
        if [ "$status" = "running" ]; then
            args=(run -d --name "$name")
            for port in $ports; do
                host_port=$(jq -r ".[$idx].Ports[\"$port\"][0].HostPort" "$JSON_BACKUP_FILE")
                if [ -n "$host_port" ]; then
                    args+=( -p "$host_port:$port" )
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
                docker "${args[@]}" 2>>"$ERROR_LOG" && loaded+=("$name") || not_loaded+=("$name")
            else
                not_loaded+=("$name")
            fi
        else
            not_loaded+=("$name")
        fi
    done
    {
        echo "[RESTORE] $(date): Loaded containers: ${loaded[*]}"
        echo "[RESTORE] $(date): Not loaded containers: ${not_loaded[*]}"
        echo "[RESTORE] Restoration log: $RESTORE_LOG"
    } | tee -a "$RESTORE_LOG"
fi

# After backup, start a background process to check Docker socket every 2 hours
start_docker_socket_monitor() {
    (
        while true; do
            if docker info >/dev/null 2>&1; then
                echo "[$(date '+%Y-%m-%d_%H-%M-%S')] Docker socket is available." >> "$ERROR_LOG"
            else
                echo "[$(date '+%Y-%m-%d_%H-%M-%S')] Docker socket is NOT available." >> "$ERROR_LOG"
            fi
            sleep 7200
        done
    ) &
}

# Start monitor after backup if not already running
if [ -f "$JSON_BACKUP_FILE" ]; then
    start_docker_socket_monitor
fi
#listen for Docker events and update the list
docker events --filter 'event=start' --filter 'event=stop' --format '{{.Status}}' | while read -r event; do
    update_c_list
done &
#listen for Docker health_status events
docker events --filter 'event=health_status' --format '{{.Actor.Attributes.name}}: {{.Status}}' | while read -r health_event; do
    echo "[HEALTH EVENT] $health_event" >> "$HEALTH_LOG"
done &
#periodically check health status of running containers
check_container_health() {
    for container in $(docker ps -q); do
        # Validate container ID before inspecting
        if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
            health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$container" 2>>"$ERROR_LOG")
            if [ $? -ne 0 ]; then
                echo "[$(date)] Error inspecting health for container $container" >> "$ERROR_LOG"
                xdg-open "$ERROR_LOG" &
            fi
            name=$(docker inspect --format='{{.Name}}' "$container" 2>>"$ERROR_LOG" | sed 's/^\///')
            if [ $? -ne 0 ]; then
                echo "[$(date)] Error inspecting name for container $container" >> "$ERROR_LOG"
                xdg-open "$ERROR_LOG" &
            fi
            echo "$(date): $name ($container) health: $health" >> "$HEALTH_LOG"
        else
            echo "[$(date)] Invalid container ID in health check: $container" >> "$ERROR_LOG"
            xdg-open "$ERROR_LOG" &
        fi
    done
}

# Debug mode: skip persistent loop and background listeners for clean validation
if [ "$DEBUG_MODE" = "1" ]; then
    echo "[DEBUG] Debug mode enabled: skipping event listeners and infinite loop."
    update_c_list
    start_saved_containers
    check_container_health
    echo "[DEBUG] Clean run complete. Exiting."
    exit 0
else
    # Immediately update container list and start any saved containers
    update_c_list
    start_saved_containers
    #listen for Docker events and update the list
    docker events --filter 'event=start' --filter 'event=stop' --format '{{.Status}}' | while read -r event; do
        update_c_list
    done &
    #listen for Docker health_status events
    docker events --filter 'event=health_status' --format '{{.Actor.Attributes.name}}: {{.Status}}' | while read -r health_event; do
        echo "[HEALTH EVENT] $health_event" >> "$HEALTH_LOG"
    done &
    #periodically check health status of running containers
    while true; do
        check_container_health
        sleep 60
    done
fi