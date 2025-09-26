#!/bin/bash
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
CONFIG_FILE_LOCAL="$SCRIPT_DIR/docker_autostart.conf"
LOCKFILE_SCRIPT_LOCAL="$SCRIPT_DIR/lockfile.sh"
CONFIG_FILE_BIN="/usr/local/bin/docker_autostart.conf"
LOCKFILE_SCRIPT_BIN="/usr/local/bin/lockfile.sh"

if [ -r "$CONFIG_FILE_LOCAL" ]; then
    CONFIG_FILE="$CONFIG_FILE_LOCAL"
elif [ -r "$CONFIG_FILE_BIN" ]; then
    CONFIG_FILE="$CONFIG_FILE_BIN"
else
    echo "[ERROR] Config file not found in local or /usr/local/bin. Exiting in 10 seconds..." >&2
    sleep 10
    exit 2
fi

if [ -r "$LOCKFILE_SCRIPT_LOCAL" ]; then
    LOCKFILE_SCRIPT="$LOCKFILE_SCRIPT_LOCAL"
elif [ -r "$LOCKFILE_SCRIPT_BIN" ]; then
    LOCKFILE_SCRIPT="$LOCKFILE_SCRIPT_BIN"
else
    echo "[ERROR] Lockfile script not found in local or /usr/local/bin. Exiting in 10 seconds..." >&2
    sleep 10
    exit 2
fi

# Source config and lockfile
. "$CONFIG_FILE"
. "$LOCKFILE_SCRIPT"

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

#trap exit for cleanup
trap cleanup EXIT SIGTERM SIGINT SIGHUP
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
    # Save images and config of running containers before exit
    IMAGE_BACKUP_DIR="$AUTOSCRIPT_DIR/image_backups"
    CONFIG_BACKUP_DIR="$AUTOSCRIPT_DIR/container_configs"
    mkdir -p "$IMAGE_BACKUP_DIR" "$CONFIG_BACKUP_DIR"
    for container in $(cat "$CONTAINER_LIST"); do
        if [[ "$container" =~ ^[a-zA-Z0-9]+$ ]]; then
            image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>>"$ERROR_LOG")
            name=$(docker inspect --format='{{.Name}}' "$container" 2>>"$ERROR_LOG" | sed 's/\///')
            if [ -n "$image" ]; then
                backup_file="$IMAGE_BACKUP_DIR/${name}_${container}.tar"
                docker save "$image" -o "$backup_file" 2>>"$ERROR_LOG"
                echo "[$(date)] Saved image $image for container $name ($container) to $backup_file" >> "$HEALTH_LOG"
            fi
            # Save container config
            docker inspect "$container" > "$CONFIG_BACKUP_DIR/${name}_${container}.json" 2>>"$ERROR_LOG"
        fi
    done
    exit 0
}
#catch shutdown/restart signal
trap save_containers SIGTERM SIGINT SIGHUP

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