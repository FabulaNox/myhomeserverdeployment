

# Simple lockfile library for bash
# Place in BOTH the script directory and /usr/local/bin for systemd/manual runs.
# Usage: source this file, then call acquire_lock <lockfile> and release_lock <lockfile>
# Source config for lockfile path if needed
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/docker_autostart.conf"
if [ -r "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

acquire_lock() {
    local lockfile="$1"
    if [ -z "$lockfile" ]; then
        echo "[LOCKFILE ERROR] lockfile path not provided" >&2
        return 2
    fi
    exec 200>"$lockfile"
    flock -n 200 && echo $$ > "$lockfile" || return 1
}

release_lock() {
    local lockfile="$1"
    if [ -z "$lockfile" ]; then
        echo "[LOCKFILE ERROR] lockfile path not provided" >&2
        return 2
    fi
    exec 200>"$lockfile"
    flock -u 200
    rm -f "$lockfile"
}
