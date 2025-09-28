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



# Set default socket paths if not set in config
SYSTEM_DOCKER_SOCKET="${SYSTEM_DOCKER_SOCKET:-unix:///var/run/docker.sock}"
DOCKER_DESKTOP_SOCKET_TEMPLATE="${DOCKER_DESKTOP_SOCKET_TEMPLATE:-unix:///run/user/{USER_ID}/docker.sock}"

# Ensure the state directory exists and is secure.
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"




# Source centralized logging, docker binary check, and per-daemon helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/docker-log-helper.sh"
source "$SCRIPT_DIR/docker-check-binary.sh"
if [[ "$DOCKER_BINARY_OK" != "1" ]]; then
    log "ERROR: docker binary not found. Aborting main script."; exit 1
fi
source "$SCRIPT_DIR/docker-save-system.sh"
source "$SCRIPT_DIR/docker-save-desktop.sh"
source "$SCRIPT_DIR/docker-restore-system.sh"
source "$SCRIPT_DIR/docker-restore-desktop.sh"



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

    # 1. Save state for the system Docker daemon (modularized)
    source "$SCRIPT_DIR/docker-save-system.sh"

    # 2. Save state for the Docker Desktop daemon, if configured (modularized)
    if [[ -n "$DOCKER_DESKTOP_USER" ]]; then
        source "$SCRIPT_DIR/docker-save-desktop.sh"
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


    # Read each line, which is now in the format "socket_path,container_name".
    while IFS=, read -r socket_path container_name; do
        if [[ -n "$socket_path" && -n "$container_name" ]]; then
            if [[ "$socket_path" == unix:///var/run/docker.sock ]]; then
                # System Docker restore (modularized)
                if restore_system_container "$socket_path" "$container_name"; then
                    ((restored_count++))
                else
                    ((failed_count++))
                fi
            elif [[ "$socket_path" =~ ^unix:///run/user/([0-9]+)/docker.sock$ ]]; then
                # Docker Desktop restore (modularized)
                user_id="${BASH_REMATCH[1]}"
                if restore_desktop_container "$user_id" "$container_name"; then
                    ((restored_count++))
                else
                    ((failed_count++))
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
