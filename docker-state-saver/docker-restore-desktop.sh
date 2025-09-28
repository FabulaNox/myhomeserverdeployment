#!/usr/bin/env bash
# docker-restore-desktop.sh
# Helper for restoring containers on the Docker Desktop daemon


# Expects: LOG_FILE, VERBOSE, FORCE, SKIP_MISSING, DRY_RUN, state_file_to_use
# Usage: source config and logging, then call this script with user_id, container_name
# Requires: docker binary available (checked via docker-check-binary.sh)

# Check required variables
for var in LOG_FILE FORCE SKIP_MISSING DRY_RUN; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set in docker-restore-desktop.sh" >&2
        return 1
    fi
done

# Check docker binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/docker-check-binary.sh"
if [[ "$DOCKER_BINARY_OK" != "1" ]]; then
    log "ERROR: docker binary not found. Aborting desktop restore."; return 1
fi

restore_desktop_container() {
    local user_id="$1"
    local container_name="$2"
    local desktop_socket="${DOCKER_DESKTOP_SOCKET_TEMPLATE//\{USER_ID\}/$user_id}"
    local desktop_socket_path="${desktop_socket#unix://}"
    local already_running=0
    local user_name
    user_name=$(getent passwd "$user_id" | cut -d: -f1)
    # Check Docker Desktop readiness (process and socket)
    if [[ -n "$user_name" && $(pgrep -u "$user_name" -f 'docker-desktop' 2>/dev/null) ]]; then
        wait_time=0
        while [[ ! -S "$desktop_socket_path" && $wait_time -lt 10 ]]; do
            sleep 1
            ((wait_time++))
        done
        if [[ -S "$desktop_socket_path" ]]; then
            if DOCKER_HOST="$desktop_socket" docker info >/dev/null 2>&1; then
                if [[ $FORCE -eq 0 ]]; then
                    if DOCKER_HOST="$desktop_socket" docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q true; then
                        log "Container '$container_name' is already running. Skipping."
                        already_running=1
                    fi
                fi
                if [[ $already_running -eq 0 ]]; then
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log "[DRY RUN] Would start: $container_name on $desktop_socket"
                        return 0
                    else
                        if DOCKER_HOST="$desktop_socket" docker start "$container_name"; then
                            log "Successfully started: $container_name"
                            return 0
                        else
                            if [[ $SKIP_MISSING -eq 1 ]]; then
                                log "Warning: Could not start container '$container_name' (may not exist). Skipping."
                            else
                                log "ERROR: Failed to start container '$container_name' on daemon at '$desktop_socket'."
                            fi
                            return 1
                        fi
                    fi
                fi
            else
                log "ERROR: Docker Desktop socket is present but not responding for user '$user_name'. Skipping restore for this socket."
                return 1
            fi
        else
            log "ERROR: Docker Desktop process is running but socket did not appear at $desktop_socket after 10 seconds. Skipping restore for this socket."
            return 1
        fi
    else
        log "Docker Desktop process is not running for user id $user_id. Skipping restore for this socket."
        return 1
    fi
}
