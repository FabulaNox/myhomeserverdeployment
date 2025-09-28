#!/usr/bin/env bash
# docker-save-desktop.sh
# Helper for saving state from the Docker Desktop daemon


# Expects: LOG_FILE, VERBOSE, status_filter, FILTER_PATTERN, TEMP_STATE_FILE, DOCKER_DESKTOP_USER
# Usage: source config and logging, then call this script
# Requires: docker binary available (checked via docker-check-binary.sh)

# Check required variables
for var in LOG_FILE status_filter FILTER_PATTERN TEMP_STATE_FILE DOCKER_DESKTOP_USER; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set in docker-save-desktop.sh" >&2
        return 1
    fi
done

# Check docker binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/docker-check-binary.sh"
if [[ "$DOCKER_BINARY_OK" != "1" ]]; then
    log "ERROR: docker binary not found. Aborting desktop save."; return 1
fi

user_id=$(id -u "$DOCKER_DESKTOP_USER" 2>/dev/null)
if [[ -n "$user_id" ]]; then
    desktop_socket="${DOCKER_DESKTOP_SOCKET_TEMPLATE//\{USER_ID\}/$user_id}"
    desktop_socket_path="${desktop_socket#unix://}"
    if pgrep -u "$DOCKER_DESKTOP_USER" -f 'docker-desktop' >/dev/null 2>&1; then
        log "Docker Desktop process detected for user '$DOCKER_DESKTOP_USER'."
        wait_time=0
        while [[ ! -S "$desktop_socket_path" && $wait_time -lt 10 ]]; do
            sleep 1
            ((wait_time++))
        done
        if [[ -S "$desktop_socket_path" ]]; then
            log "Docker Desktop socket is now available at $desktop_socket. Testing connection..."
            if DOCKER_HOST="$desktop_socket" docker info >/dev/null 2>&1; then
                log "Docker Desktop socket is working. Querying containers..."
                ps_args2=(docker ps)
                [[ -n "$status_filter" ]] && ps_args2+=(--filter "$status_filter")
                [[ -n "$FILTER_PATTERN" ]] && ps_args2+=(--filter "name=$FILTER_PATTERN")
                ps_args2+=(--format "$desktop_socket,{{.Names}}")
                if DOCKER_HOST="$desktop_socket" "${ps_args2[@]}" >> "$TEMP_STATE_FILE"; then
                    log "Docker Desktop daemon query successful."
                else
                    log "Warning: Could not query Docker Desktop daemon for user '$DOCKER_DESKTOP_USER'."
                fi
            else
                log "ERROR: Docker Desktop socket is present but not responding for user '$DOCKER_DESKTOP_USER'."
            fi
        else
            log "ERROR: Docker Desktop process is running but socket did not appear at $desktop_socket after 10 seconds."
        fi
    else
        log "Docker Desktop process is not running for user '$DOCKER_DESKTOP_USER'. Skipping Docker Desktop state save."
    fi
else
    log "Warning: Could not find UID for Docker Desktop user '$DOCKER_DESKTOP_USER'."
fi
