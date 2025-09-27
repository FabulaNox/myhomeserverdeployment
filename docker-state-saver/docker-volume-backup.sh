#!/usr/bin/env bash
#
# Docker Volume Backup - Backs up volumes from running containers.
# This script is intended to be run via a cron job.

set -o pipefail

# --- Load Configuration ---
CONFIG_FILE="/etc/docker-state-saver/saver.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # Use a simple parser for INI sections
    DOCKER_DESKTOP_USER=$(sed -n -e 's/^\s*DOCKER_DESKTOP_USER\s*=\s*"\?\([^"]*\)"\?/\1/p' "$CONFIG_FILE")
    BACKUP_DIR=$(sed -n -e 's/^\s*BACKUP_DIR\s*=\s*"\?\([^"]*\)"\?/\1/p' "$CONFIG_FILE")
    BACKUP_ROTATION_COUNT=$(sed -n -e 's/^\s*BACKUP_ROTATION_COUNT\s*=\s*"\?\([^"]*\)"\?/\1/p' "$CONFIG_FILE")
    LOG_FILE=$(sed -n -e 's/^\s*LOG_FILE\s*=\s*"\?\([^"]*\)"\?/\1/p' "$CONFIG_FILE")
else
    echo "FATAL: Configuration file $CONFIG_FILE not found." >&2
    exit 1
fi

# --- Lockfile ---
LOCK_FILE="/tmp/docker-volume-backup.lock"
if [ -e "$LOCK_FILE" ]; then
    echo "Lockfile $LOCK_FILE exists, another backup may be running." >&2
    exit 1
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

# --- Logging ---
log() {
    echo "$(date --iso-8601=seconds) - [Backup] - $1" >> "$LOG_FILE"
}

# --- Main Backup Logic ---
log "Starting volume backup process..."
mkdir -p "$BACKUP_DIR"
BACKUP_DATE=$(date +%Y-%m-%d_%H%M%S)

# Function to perform backup for a given Docker daemon
backup_daemon_volumes() {
    local DOCKER_HOST_SOCKET=$1
    local daemon_name=$2
    log "Querying daemon '$daemon_name' for containers and volumes..."

    # Get a list of running containers
    local running_containers
    running_containers=$(DOCKER_HOST="$DOCKER_HOST_SOCKET" docker ps -q --filter "status=running")

    if [ -z "$running_containers" ]; then
        log "No running containers found for daemon '$daemon_name'."
        return
    fi

    # For each container, get its volume mounts
    for container in $running_containers; do
        local container_name
        container_name=$(DOCKER_HOST="$DOCKER_HOST_SOCKET" docker inspect --format='{{.Name}}' "$container" | sed 's,^/,,' )
        local volumes
        volumes=$(DOCKER_HOST="$DOCKER_HOST_SOCKET" docker inspect --format='{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "$container")

        if [ -z "$volumes" ]; then
            log "Container '$container_name' has no volumes to back up."
            continue
        fi

        # For each volume, create a compressed archive
        while IFS= read -r volume_name; do
            log "Backing up volume '$volume_name' from container '$container_name'..."
            local backup_file="${BACKUP_DIR}/${container_name}_${volume_name}_${BACKUP_DATE}.tar.gz"
            local volume_path
            volume_path=$(DOCKER_HOST="$DOCKER_HOST_SOCKET" docker volume inspect --format '{{.Mountpoint}}' "$volume_name")

            if [ -d "$volume_path" ]; then
                if tar -czf "$backup_file" -C "$volume_path" .; then
                    log "Successfully created backup: $backup_file"

                    # Rotate old backups
                    local old_backups
                    old_backups=$(ls -1t "${BACKUP_DIR}/${container_name}_${volume_name}_"*.tar.gz | tail -n +$((BACKUP_ROTATION_COUNT + 1)))
                    if [ -n "$old_backups" ]; then
                        log "Rotating old backups for '$volume_name'..."
                        echo "$old_backups" | xargs -d '\n' rm -f
                    fi
                else
                    log "ERROR: Failed to create backup for volume '$volume_name'."
                    rm -f "$backup_file" # Clean up failed attempt
                fi
            else
                log "ERROR: Volume path '$volume_path' for volume '$volume_name' does not exist."
            fi
        done <<< "$volumes"
    done
}

# --- Execute for all daemons ---
# 1. System daemon
backup_daemon_volumes "unix:///var/run/docker.sock" "system"

# 2. Docker Desktop daemon
if [[ -n "$DOCKER_DESKTOP_USER" ]]; then
    user_id=$(id -u "$DOCKER_DESKTOP_USER" 2>/dev/null)
    if [[ -n "$user_id" ]]; then
        desktop_socket="unix:///run/user/${user_id}/docker.sock"
        if [[ -S "${desktop_socket#unix://}" ]]; then
            backup_daemon_volumes "$desktop_socket" "desktop"
        fi
    fi
fi

log "Volume backup process finished."
exit 0
