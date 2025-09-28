#!/usr/bin/env bash
# docker-restore-system.sh
# Helper for restoring containers on the system Docker daemon


# Expects: LOG_FILE, VERBOSE, FORCE, SKIP_MISSING, DRY_RUN, state_file_to_use
# Usage: source config and logging, then call this script with container_name
# Requires: docker binary available (checked via docker-check-binary.sh)

# Check required variables
for var in LOG_FILE FORCE SKIP_MISSING DRY_RUN; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set in docker-restore-system.sh" >&2
        return 1
    fi
done

# Check docker binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/docker-check-binary.sh"
if [[ "$DOCKER_BINARY_OK" != "1" ]]; then
    log "ERROR: docker binary not found. Aborting system restore."; return 1
fi

restore_system_container() {
    local socket_path="$1"
    local container_name="$2"
    # If socket_path is the default, use SYSTEM_DOCKER_SOCKET
    if [[ "$socket_path" == "unix:///var/run/docker.sock" ]]; then
        socket_path="$SYSTEM_DOCKER_SOCKET"
    fi
    local already_running=0
    if [[ $FORCE -eq 0 ]]; then
        if DOCKER_HOST="$socket_path" docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q true; then
            log "Container '$container_name' is already running. Skipping."
            already_running=1
        fi
    fi
    if [[ $already_running -eq 0 ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "[DRY RUN] Would start: $container_name on $socket_path"
            return 0
        else
            if DOCKER_HOST="$socket_path" docker start "$container_name"; then
                log "Successfully started: $container_name"
                return 0
            else
                if [[ $SKIP_MISSING -eq 1 ]]; then
                    log "Warning: Could not start container '$container_name' (may not exist). Skipping."
                else
                    log "ERROR: Failed to start container '$container_name' on daemon at '$socket_path'."
                fi
                return 1
            fi
        fi
    fi
    return 1
}
