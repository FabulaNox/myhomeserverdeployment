#!/bin/bash
# Wrapper to launch Autopsy 4.22 with a controlled environment.
# Drop this file into /usr/local/bin/autopsy-4.22 (or copy it there) and make it executable.

# Prefer a known-good Java 17 installation, but fall back to `java` on PATH.
PREFERRED_JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
if [[ -d "$PREFERRED_JAVA_HOME" ]]; then
    export JAVA_HOME="$PREFERRED_JAVA_HOME"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Try to locate the installed Autopsy launcher in common locations.
# Support both flat and nested extraction layouts and the /usr/autopsy symlink.
CANDIDATES=(
    "/usr/lib/autopsy-4.22.0/bin/autopsy"
    "/usr/lib/autopsy-4.22.0/autopsy-4.22.0/bin/autopsy"
    "/usr/autopsy/bin/autopsy"
)

LAUNCHER=""
for c in "${CANDIDATES[@]}"; do
    if [[ -x "$c" ]]; then
        LAUNCHER="$c"
        break
    fi
done

# As a last resort, search within the standard install root to depth 3
if [[ -z "$LAUNCHER" ]]; then
    LAUNCHER=$(find /usr/lib/autopsy-4.22.0 -maxdepth 3 -type f -name autopsy 2>/dev/null | head -n1)
fi

if [[ -z "$LAUNCHER" || ! -x "$LAUNCHER" ]]; then
    echo "Autopsy launcher not found or not executable in expected locations." >&2
    echo "Tried: ${CANDIDATES[*]} and a short search under /usr/lib/autopsy-4.22.0." >&2
    echo "Run the installer, or edit this wrapper to point to the correct path." >&2
    exit 2
fi

# Derive the application root from the launcher path and set LD_LIBRARY_PATH
APP_ROOT=$(dirname "$LAUNCHER")/..
LIB_DIR=$(realpath -m "$APP_ROOT/lib")
export LD_LIBRARY_PATH="$LIB_DIR:${LD_LIBRARY_PATH:-}"

# Exec the real launcher with any provided args
exec "$LAUNCHER" "$@"
