#!/usr/bin/env bash
# docker-save-system.sh
# Helper for saving state from the system Docker daemon


# Expects: LOG_FILE, VERBOSE, status_filter, FILTER_PATTERN, TEMP_STATE_FILE
# Usage: source config and logging, then call this script
# Requires: docker binary available (checked via docker-check-binary.sh)

# Check required variables
for var in LOG_FILE status_filter FILTER_PATTERN TEMP_STATE_FILE; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set in docker-save-system.sh" >&2
        return 1
    fi
done

# Check docker binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/docker-check-binary.sh"
if [[ "$DOCKER_BINARY_OK" != "1" ]]; then
    log "ERROR: docker binary not found. Aborting system save."; return 1
fi

system_socket="${SYSTEM_DOCKER_SOCKET:-unix:///var/run/docker.sock}"
if [[ -S "${system_socket#unix://}" ]]; then
    log "Querying system Docker daemon at $system_socket..."
    ps_args=(docker ps)
    [[ -n "$status_filter" ]] && ps_args+=(--filter "$status_filter")
    [[ -n "$FILTER_PATTERN" ]] && ps_args+=(--filter "name=$FILTER_PATTERN")
    ps_args+=(--format "$system_socket,{{.Names}}")
    if DOCKER_HOST="$system_socket" "${ps_args[@]}" >> "$TEMP_STATE_FILE"; then
        log "System daemon query successful."
    else
        log "Warning: Could not query system Docker daemon."
    fi
fi
