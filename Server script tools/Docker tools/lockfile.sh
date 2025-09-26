# Simple lockfile library for bash
# Usage:
#   . lockfile.sh
#   acquire_lock /path/to/lockfile || exit 1
#   ... your code ...
#   release_lock /path/to/lockfile

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
