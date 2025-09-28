#!/usr/bin/env bash
# docker-log-helper.sh
# Centralized logging and error handling for Docker State Saver scripts


# Usage: source this script and use log <message>
# Expects LOG_FILE and VERBOSE to be set in the environment
# Requires: LOG_FILE must be set

if [[ -z "$LOG_FILE" ]]; then
    echo "ERROR: LOG_FILE is not set in docker-log-helper.sh" >&2
    return 1
fi

log() {
    # Appends a timestamped message to the log file.
    # SECURITY: Sanitize container names for log output
    local msg="$1"
    msg="${msg//[$'\n\r']/ }"  # Remove newlines
    if [[ "$VERBOSE" == 1 ]]; then
        echo "$(date --iso-8601=seconds) - $msg" | tee -a "$LOG_FILE"
    else
        echo "$(date --iso-8601=seconds) - $msg" >> "$LOG_FILE"
    fi
}
