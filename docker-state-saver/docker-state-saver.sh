#!/usr/bin/env bash
#
# Docker State Saver - Saves and restores running containers across reboots.

set -o pipefail


### --- Parse global flags: --config, --log, --help ---
# SECURITY: Only use trusted config files. Do not allow untrusted users to write to the config file or its directory.
CONFIG_FILE="/etc/docker-state-saver/saver.conf"
LOG_OVERRIDE=""
SHOW_HELP=0

while [[ "$1" == --* ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"; shift 2;;
        --log)
            LOG_OVERRIDE="$2"; shift 2;;
        --help|-h)
            SHOW_HELP=1; shift;;
        *)
            break;;
    esac
done

if [[ $SHOW_HELP -eq 1 ]]; then
    echo "Usage: $0 [--config <file>] [--log <file>] <command> [flags]"
    echo "Commands:"
    echo "  save [--all] [--filter <pattern>] [--dry-run] [--verbose]"
    echo "  restore [--force] [--skip-missing] [--dry-run] [--verbose]"
    echo "  manual-save [--all] [--filter <pattern>] [--dry-run] [--verbose]"
    echo "  checkpoint-restore [--force] [--skip-missing] [--dry-run] [--rollback <file>] [--verbose]"
    echo "  --config <file>   Use alternate config file"
    echo "  --log <file>      Override log file location"
    echo "  --help, -h        Show this help message"
    exit 0
fi


# SECURITY: Validate config file ownership (must be owned by root or current user)
if [[ -f "$CONFIG_FILE" ]]; then
    config_owner=$(stat -c %U "$CONFIG_FILE")
    if [[ "$config_owner" != "root" && "$config_owner" != "$(whoami)" ]]; then
        echo "FATAL: Config file $CONFIG_FILE is not owned by root or current user ($config_owner)." >&2
        exit 1
    fi
    source "$CONFIG_FILE"
else
    echo "FATAL: Configuration file $CONFIG_FILE not found." >&2
    exit 1
fi

if [[ -n "$LOG_OVERRIDE" ]]; then
    LOG_FILE="$LOG_OVERRIDE"
fi


# Ensure the state directory exists and is secure.
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Centralized logging function.
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



# Save state with support for --all, --filter, --dry-run, --verbose
save_state() {
    # SECURITY: Trap to clean up temp files on exit or interruption
    local TEMP_STATE_FILE
    TEMP_STATE_FILE=""
    cleanup_temp() { [[ -n "$TEMP_STATE_FILE" && -f "$TEMP_STATE_FILE" ]] && rm -f "$TEMP_STATE_FILE"; }
    trap cleanup_temp EXIT INT TERM
    local SAVE_ALL=0
    local FILTER_PATTERN=""
    local DRY_RUN=0
    VERBOSE=0
    # Parse flags
    while [[ -n "$1" ]]; do
        case "$1" in
            --all|-a) SAVE_ALL=1; shift;;
            --filter) FILTER_PATTERN="$2"; shift 2;;
            --dry-run) DRY_RUN=1; shift;;
            --verbose|-v) VERBOSE=1; shift;;
            *) break;;
        esac
    done

    log "Shutdown triggered. Saving container state..."
    TEMP_STATE_FILE=$(mktemp)
    local total_count=0
    local status_filter="status=running"
    if [[ $SAVE_ALL -eq 1 ]]; then
        status_filter=""
    fi

    # 1. Save state for the system Docker daemon.
    local system_socket="unix:///var/run/docker.sock"
    if [[ -S "${system_socket#unix://}" ]]; then
        log "Querying system Docker daemon at $system_socket..."
        local ps_args=(docker ps)
        [[ -n "$status_filter" ]] && ps_args+=(--filter "$status_filter")
        [[ -n "$FILTER_PATTERN" ]] && ps_args+=(--filter "name=$FILTER_PATTERN")
        ps_args+=(--format "$system_socket,{{.Names}}")
        if DOCKER_HOST="$system_socket" "${ps_args[@]}" >> "$TEMP_STATE_FILE"; then
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
            local desktop_socket_path="/run/user/${user_id}/docker.sock"
            # Explicitly check if Docker Desktop process is running
            if pgrep -u "$DOCKER_DESKTOP_USER" -f 'docker-desktop' >/dev/null 2>&1; then
                log "Docker Desktop process detected for user '$DOCKER_DESKTOP_USER'."
                # Wait for the socket to appear (up to 10 seconds)
                local wait_time=0
                while [[ ! -S "$desktop_socket_path" && $wait_time -lt 10 ]]; do
                    sleep 1
                    ((wait_time++))
                done
                if [[ -S "$desktop_socket_path" ]]; then
                    log "Docker Desktop socket is now available at $desktop_socket. Testing connection..."
                    # Test the socket by running a simple docker command
                    if DOCKER_HOST="$desktop_socket" docker info >/dev/null 2>&1; then
                        log "Docker Desktop socket is working. Querying containers..."
                        local ps_args2=(docker ps)
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
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY RUN] Would save the following containers:"
        cat "$TEMP_STATE_FILE"
        cleanup_temp
        trap - EXIT INT TERM
        return 0
    fi

    # Finalize the state file using STATE_FILE from config.
    mv "$TEMP_STATE_FILE" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    total_count=$(wc -l < "$STATE_FILE")
    log "Successfully saved state for $total_count container(s) from all daemons to $STATE_FILE."
    trap - EXIT INT TERM
}


# Restore state with support for --force, --skip-missing, --dry-run, --verbose, --rollback
restore_state() {
    # SECURITY: Trap to clean up temp files on exit or interruption (if any are used)
    trap '' EXIT INT TERM
    local FORCE=0
    local SKIP_MISSING=0
    local DRY_RUN=0
    local ROLLBACK_FILE=""
    VERBOSE=0
    # Parse flags
    while [[ -n "$1" ]]; do
        case "$1" in
            --force|-f) FORCE=1; shift;;
            --skip-missing) SKIP_MISSING=1; shift;;
            --dry-run) DRY_RUN=1; shift;;
            --rollback) ROLLBACK_FILE="$2"; shift 2;;
            --verbose|-v) VERBOSE=1; shift;;
            *) break;;
        esac
    done

    log "System startup. Restoring container state from all daemons..."

    local state_file_to_use="$STATE_FILE"
    if [[ -n "$ROLLBACK_FILE" ]]; then
        state_file_to_use="$ROLLBACK_FILE"
    fi
    if [[ ! -f "$state_file_to_use" ]]; then
        log "State file $state_file_to_use not found. Nothing to restore."
        return 0
    fi

    chmod 600 "$state_file_to_use"

    if [[ ! -s "$state_file_to_use" ]]; then
        log "State file is empty. No containers to restore."
        return 0
    fi

    local restored_count=0
    local failed_count=0


    # Track Docker Desktop socket readiness for each user/socket
    declare -A desktop_socket_ready

    # Read each line, which is now in the format "socket_path,container_name".
    while IFS=, read -r socket_path container_name; do
        if [[ -n "$socket_path" && -n "$container_name" ]]; then
            # Detect if this is a Docker Desktop socket
            if [[ "$socket_path" =~ ^unix:///run/user/([0-9]+)/docker.sock$ ]]; then
                user_id="${BASH_REMATCH[1]}"
                desktop_socket_path="/run/user/${user_id}/docker.sock"
                desktop_socket="unix:///run/user/${user_id}/docker.sock"
                # Only check readiness once per socket
                if [[ -z "${desktop_socket_ready[$desktop_socket]}" ]]; then
                    # Check if Docker Desktop process is running for this user
                    user_name=$(getent passwd "$user_id" | cut -d: -f1)
                    if [[ -n "$user_name" && $(pgrep -u "$user_name" -f 'docker-desktop' 2>/dev/null) ]]; then
                        log "Docker Desktop process detected for user '$user_name' (uid $user_id)."
                        # Wait for the socket to appear (up to 10 seconds)
                        wait_time=0
                        while [[ ! -S "$desktop_socket_path" && $wait_time -lt 10 ]]; do
                            sleep 1
                            ((wait_time++))
                        done
                        if [[ -S "$desktop_socket_path" ]]; then
                            log "Docker Desktop socket is now available at $desktop_socket. Testing connection..."
                            if DOCKER_HOST="$desktop_socket" docker info >/dev/null 2>&1; then
                                log "Docker Desktop socket is working. Proceeding with restore."
                                desktop_socket_ready[$desktop_socket]=1
                            else
                                log "ERROR: Docker Desktop socket is present but not responding for user '$user_name'. Skipping restore for this socket."
                                desktop_socket_ready[$desktop_socket]=0
                                continue
                            fi
                        else
                            log "ERROR: Docker Desktop process is running but socket did not appear at $desktop_socket after 10 seconds. Skipping restore for this socket."
                            desktop_socket_ready[$desktop_socket]=0
                            continue
                        fi
                    else
                        log "Docker Desktop process is not running for user id $user_id. Skipping restore for this socket."
                        desktop_socket_ready[$desktop_socket]=0
                        continue
                    fi
                fi
                # If readiness check failed, skip
                if [[ "${desktop_socket_ready[$desktop_socket]}" != "1" ]]; then
                    continue
                fi
            fi
            log "Attempting to start container '$container_name' on daemon at '$socket_path'..."
            # Set DOCKER_HOST to target the correct daemon for the start command.
            local already_running=0
            if [[ $FORCE -eq 0 ]]; then
                # Check if already running
                if DOCKER_HOST="$socket_path" docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q true; then
                    log "Container '$container_name' is already running. Skipping."
                    already_running=1
                fi
            fi
            if [[ $already_running -eq 0 ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log "[DRY RUN] Would start: $container_name on $socket_path"
                    ((restored_count++))
                else
                    if DOCKER_HOST="$socket_path" docker start "$container_name"; then
                        log "Successfully started: $container_name"
                        ((restored_count++))
                    else
                        if [[ $SKIP_MISSING -eq 1 ]]; then
                            log "Warning: Could not start container '$container_name' (may not exist). Skipping."
                        else
                            log "ERROR: Failed to start container '$container_name' on daemon at '$socket_path'."
                        fi
                        ((failed_count++))
                    fi
                fi
            fi
        fi
    done < "$state_file_to_use"

    log "Restore complete. Started: $restored_count, Failed: $failed_count."
}


# Manual save function (can be called by a sudo-level command)
manual_save() {
    log "Manual save triggered by user $(whoami)"
    # SECURITY: Set restrictive permissions on log file
    touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
    save_state "$@"
    log "Manual save completed."
}

# Manual checkpoint-restore function (force restore from last save list)
checkpoint_restore() {
    log "Manual checkpoint-restore triggered by user $(whoami) (ignoring current state)"
    # SECURITY: Set restrictive permissions on log file
    touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
    restore_state "$@"
    log "Manual checkpoint-restore completed."
}


# Main logic: decide which action to perform based on the first non-flag argument.
COMMAND="$1"; shift
case "$COMMAND" in
    save)
        save_state "$@"
        ;;
    restore)
        restore_state "$@"
        ;;
    manual-save)
        manual_save "$@"
        ;;
    checkpoint-restore)
        checkpoint_restore "$@"
        ;;
    *)
        echo "Usage: $0 [--config <file>] [--log <file>] <command> [flags]" >&2
        echo "Try '$0 --help' for more information."
        exit 1
        ;;
esac

exit 0
