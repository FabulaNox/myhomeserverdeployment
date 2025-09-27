#!/usr/bin/env bash
#
# Docker State Saver - Saves and restores running containers across reboots.
# This script is intended to be run by the docker-state-saver.service systemd unit.
# It must be placed in /usr/local/bin/

set -o pipefail

# Load configuration from a central location.
CONFIG_FILE="/etc/docker-state-saver/saver.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    # Fallback if config is missing, though installation should prevent this.
    echo "FATAL: Configuration file $CONFIG_FILE not found." >&2
    exit 1
fi

# Ensure the state directory exists.
mkdir -p "$STATE_DIR"

# Centralized logging function.
log() {
    # Appends a timestamped message to the log file.
    echo "$(date --iso-8601=seconds) - $1" >> "$LOG_FILE"
}

save_state() {
    log "Shutdown triggered. Saving running container state..."
    # Use a temporary file to aggregate containers from all daemons.
    local TEMP_STATE_FILE
    TEMP_STATE_FILE=$(mktemp)
    local total_count=0

    # 1. Save state for the system Docker daemon.
    local system_socket="unix:///var/run/docker.sock"
    if [[ -S "${system_socket#unix://}" ]]; then
        log "Querying system Docker daemon at $system_socket..."
        if DOCKER_HOST="$system_socket" docker ps --filter "status=running" --format "$system_socket,{{.Names}}" >> "$TEMP_STATE_FILE"; then
            log "System daemon query successful."
        else
            log "Warning: Could not query system Docker daemon."
        fi
    fi

    # 2. Save state for the Docker Desktop daemon, if configured.
    if [[ -n "$DOCKER_DESKTOP_USER" ]]; then
        local user_id
        user_id=$(id -u "$DOCKER_DESKTOP_USER" 2>/dev/null)
        if [[ -n "$user_id" ]]; then
            local desktop_socket="unix:///run/user/${user_id}/docker.sock"
            if [[ -S "${desktop_socket#unix://}" ]]; then
                log "Querying Docker Desktop daemon for user '$DOCKER_DESKTOP_USER' at $desktop_socket..."
                if DOCKER_HOST="$desktop_socket" docker ps --filter "status=running" --format "$desktop_socket,{{.Names}}" >> "$TEMP_STATE_FILE"; then
                    log "Docker Desktop daemon query successful."
                else
                    log "Warning: Could not query Docker Desktop daemon for user '$DOCKER_DESKTOP_USER'."
                fi
            else
                log "Warning: Docker Desktop socket not found at $desktop_socket for user '$DOCKER_DESKTOP_USER'."
            fi
        else
            log "Warning: Could not find UID for Docker Desktop user '$DOCKER_DESKTOP_USER'."
        fi
    fi

    # Finalize the state file.
    mv "$TEMP_STATE_FILE" "$STATE_FILE"
    total_count=$(wc -l < "$STATE_FILE")
    log "Successfully saved state for $total_count container(s) from all daemons to $STATE_FILE."
}

restore_state() {
    log "System startup. Restoring container state from all daemons..."
    if [[ ! -f "$STATE_FILE" ]]; then
        log "State file $STATE_FILE not found. Nothing to restore."
        return 0
    fi

    if [[ ! -s "$STATE_FILE" ]]; then
        log "State file is empty. No containers to restore."
        return 0
    fi

    local restored_count=0
    local failed_count=0

    # Read each line, which is now in the format "socket_path,container_name".
    while IFS=, read -r socket_path container_name; do
        if [[ -n "$socket_path" && -n "$container_name" ]]; then
            log "Attempting to start container '$container_name' on daemon at '$socket_path'..."
            # Set DOCKER_HOST to target the correct daemon for the start command.
            if DOCKER_HOST="$socket_path" docker start "$container_name"; then
                log "Successfully started: $container_name"
                ((restored_count++))
            else
                log "ERROR: Failed to start container '$container_name' on daemon at '$socket_path'."
                ((failed_count++))
            fi
        fi
    done < "$STATE_FILE"

    log "Restore complete. Started: $restored_count, Failed: $failed_count."
}

# Main logic: decide which action to perform based on the first argument.
case "$1" in
    save)
        save_state
        ;;
    restore)
        restore_state
        ;;
    *)
        echo "Usage: $0 {save|restore}" >&2
        exit 1
        ;;
esac

exit 0
