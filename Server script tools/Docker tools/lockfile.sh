# Simple lockfile library for bash
# Usage:
#   . lockfile.sh
#   acquire_lock /path/to/lockfile || exit 1
#   ... your code ...
#   release_lock /path/to/lockfile

acquire_lock() {
    local lockfile="$1"
    exec 200>"$LOCKFILE"
    flock -n 200 && echo $$ > "$LOCKFILE" || return 1
}

release_lock() {
    local lockfile="$1"
    exec 200>"$LOCKFILE"
    flock -u 200
    rm -f "$LOCKFILE"
}
