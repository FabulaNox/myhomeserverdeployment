# Simple lockfile library for bash
# Place this file in BOTH the script directory and /usr/local/bin for systemd/manual runs.
# Usage: source this file, then call acquire_lock <lockfile> and release_lock <lockfile>
# Returns 1 if lock cannot be acquired (already running)

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
