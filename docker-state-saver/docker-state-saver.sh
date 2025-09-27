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
    # Use 'docker ps' to get the names of all currently running containers.
    # This is the most reliable way to capture the state at shutdown.
    if ! docker ps --filter "status=running" --format '{{.Names}}' > "$STATE_FILE"; then
        log "ERROR: Failed to get running container list from Docker daemon."
        # Create an empty file to prevent errors on the next boot.
        : > "$STATE_FILE"
        return 1
    fi
    local count
    count=$(wc -l < "$STATE_FILE")
    log "Successfully saved state for $count container(s) to $STATE_FILE."
}

restore_state() {
    log "System startup. Restoring container state..."
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

    # Read each line (container name) from the state file and start it.
    while IFS= read -r container_name; do
        if [[ -n "$container_name" ]]; then
            log "Attempting to start container: $container_name"
            if docker start "$container_name"; then
                log "Successfully started: $container_name"
                ((restored_count++))
            else
                log "ERROR: Failed to start container: $container_name"
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
