# Simple lockfile library for bash
acquire_lock() {
    local lockfile="$1"
    exec 200>"$lockfile"
    flock -n 200 && echo $$ > "$lockfile" || return 1
}

release_lock() {
    local lockfile="$1"
    exec 200>"$lockfile"
    flock -u 200
    rm -f "$lockfile"
}
