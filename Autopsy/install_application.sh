#!/bin/bash
# This script installs the Autopsy application on a Linux system.
#
# Technical checklist (high-level phases)
# 1) Preparation
#    - Ensure system has basic tools (apt-get update/install of core packages).
#    - Create DOWNLOAD_DIR and set default paths for tarball, .deb and Autopsy zip.
#    - Inputs: optional flags (-a artifacts dir, -p jar, -s so, -b no-build, -v verbose)
#    - Output: download placeholders present in DOWNLOAD_DIR (may be skipped if present)
#    - Side-effects: may add Bullseye apt source temporarily.
#
# 2) Dependency installation
#    - Install runtime/build packages required for Autopsy and Sleuth Kit (ant, openjdk, build tools, libs).
#    - Error modes: apt installation failures, missing repos on older distros.
#
# 3) Artifact resolution (preferred order)
#    - explicit (-p/-s) -> artifacts dir (-a) -> install .deb -> provided archive (zip/tar) -> source build
#    - If NO_BUILD (-b) and no artifacts found, fail fast (explicit by design).
#    - Outputs: TSK_JAR_PATH and TSK_SO_PATH when discovered; SKIP_BUILD toggled when artifacts available.
#
# 4) (Optional) Install .deb or build Sleuth Kit from source
#    - If .deb provided it'll be dpkg -i installed (and attempted repairs via apt-get -f).
#    - If building: check_build_deps() runs to list missing commands/packages; then bootstrap/configure/make/ant.
#    - Error modes: compilation failures, missing dev headers; check_build_deps prints apt-get suggestion.
#
# 5) Copy/install JNI artifacts into Autopsy lib
#    - Create APPLICATION_INSTALL_DIR/lib and copy tsk_jni.jar and libtsk_jni.so from discovered/package/build locations.
#    - Also ensure fallback copies from common library locations if necessary.
#    - Output: Application-local copy of jar and .so used at runtime.
#
# 6) Extract Autopsy and run unix_setup.sh
#    - Unzip Autopsy into APPLICATION_INSTALL_DIR and run unix_setup.sh -j JAVA_PATH -n APPLICATION_NAME
#    - Temporary system symlink may be created in /usr/share/java to satisfy unix_setup.sh expectations.
#
# 7) Finalization (cleanup + smoke-check)
#    - Remove temporary symlink only if it points to our created/discovered jar.
#    - Verify jar and .so are present in APPLICATION_INSTALL_DIR/lib; if missing attempt to copy from discovered paths or package.
#    - Fail fast with clear diagnostics if artifacts remain missing.
#
# 8) Idempotence and safety notes
#    - Many copy operations use sudo and || true to avoid fatal failures during checks.
#    - The script attempts to be idempotent: multiple runs should converge to a working state.
#    - Side-effects: may modify apt sources, install packages, write to /usr/lib and /usr/share/java, and run ldconfig.
#

# Usage and option parsing
usage() {
    echo "Usage: install_application.sh [-z zip_path] [-i install_directory] [-j java_home] [-n application_name] [-D download_dir] [-a artifacts_dir] [-p tsk_jar_path] [-s tsk_so_path] [-b no-build] [-v verbose]" 1>&2
}

VERBOSE=0
DOWNLOAD_DIR=""

# Options:
# -a <dir> : artifacts directory containing a sleuthkit jar and libtsk_jni.so
# -p <file>: explicit path to tsk_jni.jar
# -s <file>: explicit path to libtsk_jni.so
# -b       : no-build mode (fail if JNI artifacts are not available)
while getopts "n:z:i:j:D:a:p:s:vb" o; do
    case "${o}" in
    n) APPLICATION_NAME=${OPTARG} ;;
    z) APPLICATION_ZIP_PATH=${OPTARG} ;;
    i) INSTALL_DIR=${OPTARG} ;;
    j) JAVA_PATH=${OPTARG} ;;
    D) DOWNLOAD_DIR=${OPTARG} ;;
    a) ARTIFACTS_DIR=${OPTARG} ;;
    p) TSK_JAR_USER=${OPTARG} ;;
    s) TSK_SO_USER=${OPTARG} ;;
    v) VERBOSE=1 ;;
    b) NO_BUILD=1 ;;
    *) usage; exit 1 ;;
    esac
done

# user-provided artifacts / no-build default values
ARTIFACTS_DIR="${ARTIFACTS_DIR:-}"
TSK_JAR_USER="${TSK_JAR_USER:-}"
TSK_SO_USER="${TSK_SO_USER:-}"
NO_BUILD=${NO_BUILD:-0}

# Helper to run commands (always executes; prints when verbose)
run() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "[RUN] $*"
    fi
    cmd="$*"
    bash -c "$cmd"
}

# Default application/install locations (can be overridden with -i)
APPLICATION_NAME="${APPLICATION_NAME:-autopsy}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"
INSTALL_DIR="${INSTALL_DIR:-/usr/lib}"
APPLICATION_INSTALL_DIR="${INSTALL_DIR}/${APPLICATION_NAME}-4.22.0"
# Where Sleuth Kit source/archive will be unpacked and built when needed.
# We use /usr/lib/sleuthkit-4.14.0 so the source tree and artifacts live under
# a predictable system path. The script will chown this dir to the current
# user before attempting an in-place build.
BUILD_DIR="/usr/lib/sleuthkit-4.14.0"
# BUILD_DIR policy:
# - Sleuth Kit sources and build artifacts are placed in $BUILD_DIR so the
#   location is consistent across systems and the installer can reliably
#   find built jars and shared libraries.
# - The installer will ensure $BUILD_DIR is owned by the invoking user
#   before running an in-place build, then move/copy final artifacts into
#   the Autopsy install area.
# - To override the build location, edit BUILD_DIR above or export a
#   different path before running the script. (A CLI flag can be added if
#   you prefer an override option.)

# Install prerequisites
print_install_plan() {
        cat <<-EOF

Installer will use the following paths (change via flags or env as noted):

    Application install dir: $APPLICATION_INSTALL_DIR
    Sleuth Kit build dir:    $BUILD_DIR
    Downloads dir:          $DOWNLOAD_DIR
    SleuthKit tarball path: $TARBALL_PATH
    SleuthKit .deb path:    $DEB_PATH
    Autopsy zip path:       $AUTOPSY_DL_PATH

Available flags:
    -n <application_name>   : Set application name (default: autopsy)
    -i <install_directory>  : Base install directory (default: /usr/lib)
    -j <java_home>          : JAVA_HOME to use for setup (default: /usr/lib/jvm/java-17-openjdk-amd64)
    -D <download_dir>       : Directory to store downloads (default: ~/Downloads)
    -a <artifacts_dir>      : Directory containing sleuthkit jar and libtsk_jni.so (used as fallback)
    -p <tsk_jar_path>       : Explicit path to tsk_jni.jar (used as fallback)
    -s <tsk_so_path>        : Explicit path to libtsk_jni.so (used as fallback)
    -b                      : NO_BUILD - skip source build and require artifacts be present (fail if not)
    -v                      : Verbose output

Examples:
    # Typical install using artifacts directory as fallback (build will still run):
    bash install_application.sh -v -a /path/to/Autopsy/artifacts

    # Provide explicit artifacts (jar and so) when they're stored elsewhere:
    bash install_application.sh -v -p /home/user/Downloads/sleuthkit-4.14.0.jar -s /home/user/Downloads/libtsk_jni.so

    # Run without building (fail if artifacts not present):
    bash install_application.sh -b -a /path/to/Autopsy/artifacts

Notes on non-standard paths:
    - If you use -i to set a non-standard install root, the application will be installed to
        <install_root>/${APPLICATION_NAME}-4.22.0. Pass -n to change the application name if needed.
    - If you set BUILD_DIR via environment before running the script (export BUILD_DIR=/some/path),
        the script will use that. Alternatively edit BUILD_DIR in the script manually.

EOF
}

# Enforce running from the downloads directory by default
PWD_REAL=$(realpath "./")
DL_REAL=$(realpath "$DOWNLOAD_DIR")
if [[ "$PWD_REAL" != "$DL_REAL" && -z "$SKIP_PWD_CHECK" ]]; then
        cat <<-EOF
Warning: this installer is intended to be run from your downloads directory (recommended):
    $DOWNLOAD_DIR

Continuing from the current directory: $PWD_REAL

Recommended: copy or move the script into the downloads directory and run it there:
    cp "$(realpath "$0")" "$DOWNLOAD_DIR/"
    cd "$DOWNLOAD_DIR" && bash "$(basename "$0")" [options]

If you intentionally want to run from another directory, set the environment variable
    SKIP_PWD_CHECK=1
and re-run the script. Running from the repository folder is allowed but not recommended.
EOF
        # continue rather than exit; assume user may not have the file in Downloads
fi

# Print the planned paths and flags before making system changes
print_install_plan

# If running interactively, allow the user to press Enter to accept defaults
# and continue. Any non-empty input aborts so the user can re-run with flags.
if [ -t 0 ]; then
    echo
    read -r -p $'Press ENTER to continue with the above defaults,
or type flags (for example: -i /opt -v) then ENTER to re-run with those flags,
or type a full command (for example: bash /path/to/install_application.sh -D /tmp) and ENTER:
' _RESP
    resp_trim="$(echo "$_RESP" | xargs)"
    if [[ -z "$resp_trim" ]]; then
        # user accepted defaults, continue
        :
    else
        # If the input looks like flags (starts with -) re-exec this script with them
        if [[ "$resp_trim" == -* ]]; then
            echo "Re-running installer with flags: $resp_trim"
            exec bash "$0" $resp_trim
        fi
        # If the input looks like a full command, execute it
        if [[ "$resp_trim" == bash* || "$resp_trim" == */* || "$resp_trim" == *.sh* ]]; then
            echo "Executing provided command: $resp_trim"
            eval "$resp_trim"
            exit $?
        fi
        # Otherwise, be conservative and abort so user can re-run correctly
        echo "Unrecognized input; aborting so you can re-run with the desired flags."
        exit 1
    fi
fi

run "sudo apt-get update"
run "sudo apt-get install -y build-essential autoconf libtool automake git zip wget ant ant-optional openjdk-17-jdk openjdk-17-jre"

# Download required packages (Sleuth Kit 4.14.0)
# Use DOWNLOAD_DIR if provided via -D, otherwise default to ~/Downloads
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"
mkdir -p "$DOWNLOAD_DIR"

TARBALL_NAME="sleuthkit-4.14.0.tar.gz"
DEB_NAME="sleuthkit-java_4.14.0-1_amd64.deb"
AUTOPSY_ZIP_NAME="autopsy-4.22.0.zip"

TARBALL_PATH="$DOWNLOAD_DIR/$TARBALL_NAME"
DEB_PATH="$DOWNLOAD_DIR/$DEB_NAME"
AUTOPSY_DL_PATH="$DOWNLOAD_DIR/$AUTOPSY_ZIP_NAME"

TARBALL_URL="https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-4.14.0/$TARBALL_NAME"
DEB_URL="https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-4.14.0/$DEB_NAME"
AUTOPSY_URL="https://github.com/sleuthkit/autopsy/releases/download/autopsy-4.22.0/$AUTOPSY_ZIP_NAME"

if [ -f "$TARBALL_PATH" ]; then
    echo "Found $TARBALL_PATH, skipping download."
else
    echo "Downloading $TARBALL_NAME to $DOWNLOAD_DIR..."
    run "wget -c -O \"$TARBALL_PATH\" \"$TARBALL_URL\""
fi

if [ -f "$DEB_PATH" ]; then
    echo "Found $DEB_PATH, skipping download."
else
    echo "Downloading $DEB_NAME to $DOWNLOAD_DIR..."
    run "wget -c -O \"$DEB_PATH\" \"$DEB_URL\""
fi

if [ -f "$AUTOPSY_DL_PATH" ]; then
    echo "Found $AUTOPSY_DL_PATH, skipping download."
else
    echo "Downloading $AUTOPSY_ZIP_NAME to $DOWNLOAD_DIR..."
    run "wget -c -O \"$AUTOPSY_DL_PATH\" \"$AUTOPSY_URL\""
fi

# Install Java 17 from Bullseye
run "echo \"deb http://deb.debian.org/debian bullseye main\" | sudo tee /etc/apt/sources.list.d/bullseye.list > /dev/null"
run "if ! grep -q \"deb http://deb.debian.org/debian bullseye main\" /etc/apt/sources.list.d/bullseye.list; then echo \"Failed to add Bullseye apt source\" >&2; exit 1; fi"
run "sudo apt update"
run "sudo apt install -t bullseye openjdk-17-jdk openjdk-17-jre -y"
run "update-java-alternatives -l | grep java-1.17 || true"




# Resolve artifacts in the preferred order:
# 1) explicit user-provided paths (-p and -s)
# 2) artifacts directory (-a) containing tsk_jni.jar and libtsk_jni.so
# 3) installed .deb package
# 4) provided sleuthkit zip/tar in DOWNLOAD_DIR
# If NO_BUILD=1 and none are present, fail fast.
SKIP_BUILD=0

# search_for_artifacts: look in common locations (Downloads, HOME, artifacts dir,
# system java/lib paths, /opt and apt cache) for tsk_jni.jar (or sleuthkit-*.jar)
# and libtsk_jni.so. If both are found, set TSK_JAR_PATH and TSK_SO_PATH and
# return success (0). This helps when the user provided artifacts but kept them
# outside the expected `-a` artifacts directory.
search_for_artifacts() {
    echo "Searching common locations for Sleuth Kit JNI artifacts..."
    local search_dirs=()
    search_dirs+=("${DOWNLOAD_DIR:-$HOME/Downloads}" "${HOME}")
    if [[ -n "${ARTIFACTS_DIR:-}" ]]; then
        search_dirs+=("$ARTIFACTS_DIR")
    fi
    search_dirs+=(/usr/share/java /usr/lib /usr/lib64 /usr/local/lib /opt /var/cache/apt/archives /tmp)

    for d in "${search_dirs[@]}"; do
        [[ -d "$d" ]] || continue
        # limit depth so the search is reasonably fast for common layouts
        found_jar=$(find "$d" -maxdepth 4 -type f \( -iname 'tsk_jni.jar' -o -iname 'sleuthkit-*.jar' \) 2>/dev/null | head -n1 || true)
        found_so=$(find "$d" -maxdepth 4 -type f -iname 'libtsk_jni.so' 2>/dev/null | head -n1 || true)
        if [[ -n "$found_jar" && -n "$found_so" ]]; then
            echo "Found artifacts in $d: $found_jar and $found_so"
            PROVIDED_TSK_JAR="$found_jar"
            PROVIDED_TSK_SO="$found_so"
            TSK_JAR_PATH="$PROVIDED_TSK_JAR"
            TSK_SO_PATH="$PROVIDED_TSK_SO"
            # Do NOT set SKIP_BUILD here; we always prefer to build and then
            # use these artifacts as a failsafe if the build doesn't produce them.
            return 0
        fi
    done

    # As a last resort, perform a wider filesystem search (may be slow).
    # Only run if we didn't already find both artifacts.
    if [[ -z "$TSK_JAR_PATH" || -z "$TSK_SO_PATH" ]]; then
        echo "Performing a wider filesystem search for Sleuth Kit artifacts (may be slow)..."
        # Try to avoid crossing network mounts with -xdev; may still need sudo for full results
        found_jar=$(find / -xdev -type f \( -iname 'tsk_jni.jar' -o -iname 'sleuthkit-*.jar' \) 2>/dev/null | head -n1 || true)
        found_so=$(find / -xdev -type f -iname 'libtsk_jni.so' 2>/dev/null | head -n1 || true)
        if [[ -n "$found_jar" && -n "$found_so" ]]; then
            echo "Found artifacts system-wide: $found_jar and $found_so"
            PROVIDED_TSK_JAR="$found_jar"
            PROVIDED_TSK_SO="$found_so"
            TSK_JAR_PATH="$PROVIDED_TSK_JAR"
            TSK_SO_PATH="$PROVIDED_TSK_SO"
            # Do NOT set SKIP_BUILD here; keep build as primary path.
            return 0
        fi
    fi
    return 1
}

# 1) explicit paths
if [[ -n "$TSK_JAR_USER" && -n "$TSK_SO_USER" && -f "$TSK_JAR_USER" && -f "$TSK_SO_USER" ]]; then
    echo "User provided artifacts: $TSK_JAR_USER and $TSK_SO_USER (will be used as fallback if build doesn't produce artifacts)"
    PROVIDED_TSK_JAR="$TSK_JAR_USER"
    PROVIDED_TSK_SO="$TSK_SO_USER"
    # keep TSK_* set so NO_BUILD mode can still use these; do NOT skip build.
    TSK_JAR_PATH="$PROVIDED_TSK_JAR"
    TSK_SO_PATH="$PROVIDED_TSK_SO"
fi

# 2) artifacts directory
if [[ "$SKIP_BUILD" -eq 0 && -n "$ARTIFACTS_DIR" && -d "$ARTIFACTS_DIR" ]]; then
    A_JAR=$(ls "$ARTIFACTS_DIR"/tsk_jni.jar 2>/dev/null | head -n1 || true)
    A_JAR2=$(ls "$ARTIFACTS_DIR"/sleuthkit-*.jar 2>/dev/null | head -n1 || true)
    A_SO=$(ls "$ARTIFACTS_DIR"/libtsk_jni.so 2>/dev/null | head -n1 || true)
    if [[ -n "$A_JAR" && -n "$A_SO" ]]; then
        echo "Artifacts found in $ARTIFACTS_DIR (will be used as fallback if build doesn't produce artifacts)"
        PROVIDED_TSK_JAR="$A_JAR"
        PROVIDED_TSK_SO="$A_SO"
        TSK_JAR_PATH="$PROVIDED_TSK_JAR"
        TSK_SO_PATH="$PROVIDED_TSK_SO"
    elif [[ -n "$A_JAR2" && -n "$A_SO" ]]; then
        echo "Artifacts found in $ARTIFACTS_DIR (will be used as fallback if build doesn't produce artifacts)"
        PROVIDED_TSK_JAR="$A_JAR2"
        PROVIDED_TSK_SO="$A_SO"
        TSK_JAR_PATH="$PROVIDED_TSK_JAR"
        TSK_SO_PATH="$PROVIDED_TSK_SO"
    fi
fi

# 3) try .deb if still not found
if [[ "$SKIP_BUILD" -eq 0 && -f "$DEB_PATH" ]]; then
    echo "Installing $DEB_PATH..."
    run "sudo dpkg -i \"$DEB_PATH\" || sudo apt-get install -f -y"
    if dpkg -s sleuthkit-java 2>/dev/null | grep -q "Status:.*installed"; then
        echo "sleuthkit-java package installed via .deb"
        PKG_JAR=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'tsk_jni.jar' || true)
        PKG_JAR2=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'sleuthkit-*.jar' || true)
        PKG_SO=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'libtsk_jni.so' || true)
        if [[ -n "$PKG_JAR" && -n "$PKG_SO" ]]; then
            echo "Package provides JNI artifacts; recording as fallback"
            PROVIDED_TSK_JAR="$PKG_JAR"
            PROVIDED_TSK_SO="$PKG_SO"
            TSK_JAR_PATH="$PROVIDED_TSK_JAR"
            TSK_SO_PATH="$PROVIDED_TSK_SO"
        elif [[ -n "$PKG_JAR2" && -n "$PKG_SO" ]]; then
            echo "Package provides JNI artifacts; recording as fallback"
            PROVIDED_TSK_JAR="$PKG_JAR2"
            PROVIDED_TSK_SO="$PKG_SO"
            TSK_JAR_PATH="$PROVIDED_TSK_JAR"
            TSK_SO_PATH="$PROVIDED_TSK_SO"
        else
            echo "Package installed but JNI artifacts not found; continuing to check provided archives"
        fi
    else
        echo "Failed to install sleuthkit-java .deb; continuing to check provided archives"
    fi
fi

# If artifacts still not found, try searching common locations (useful when
# the user provided artifacts but kept them in a non-standard place).
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if search_for_artifacts; then
        echo "Artifacts located by search: $TSK_JAR_PATH and $TSK_SO_PATH"
    fi
fi

# 4) check provided archives (ZIP/TAR) only if still not satisfied
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "No suitable artifacts from .deb or provided explicit files; checking for provided sleuthkit archive in $DOWNLOAD_DIR..."
    SLEUTH_ZIP=$(ls "$DOWNLOAD_DIR"/sleuthkit-*.zip 2>/dev/null | head -n1 || true)
    SLEUTH_TAR=$(ls "$DOWNLOAD_DIR"/sleuthkit-*.tar.gz 2>/dev/null | head -n1 || true)

    # Extract into a temporary directory then move into $BUILD_DIR under /usr/lib
    TMP_EXTRACT_DIR=$(mktemp -d -t sleuthkit-extract-XXXX)
    EXTRACTED=0
    if [[ -n "$SLEUTH_ZIP" ]]; then
        echo "Found sleuthkit ZIP: $SLEUTH_ZIP - extracting"
        run "unzip -o \"$SLEUTH_ZIP\" -d \"$TMP_EXTRACT_DIR\""
        EXTRACTED=1
    elif [[ -n "$SLEUTH_TAR" && -f \"$SLEUTH_TAR\" ]]; then
        echo "Found sleuthkit tarball: $SLEUTH_TAR - extracting"
        run "tar -xzf \"$SLEUTH_TAR\" -C \"$TMP_EXTRACT_DIR\""
        EXTRACTED=1
    elif [[ -f \"$TARBALL_PATH\" ]]; then
        echo "Extracting Sleuth Kit tarball from $TARBALL_PATH..."
        run "tar -xzf \"$TARBALL_PATH\" -C \"$TMP_EXTRACT_DIR\""
        EXTRACTED=1
    else
        echo "No sleuthkit archive found in $DOWNLOAD_DIR and $TARBALL_PATH"
    fi

    if [[ "$EXTRACTED" -eq 1 ]]; then
        # Determine the top-level directory inside the tmp extract (if any)
        EXTRACTED_SUBDIR=$(find "$TMP_EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)
        if [[ -z "$EXTRACTED_SUBDIR" ]]; then
            # Nothing was extracted into a subdir; use the tmp dir itself
            EXTRACTED_SUBDIR="$TMP_EXTRACT_DIR"
        fi
        # Ensure target build dir is clean and move extracted tree into place
        run "sudo rm -rf \"$BUILD_DIR\" || true"
        run "sudo mv \"$EXTRACTED_SUBDIR\" \"$BUILD_DIR\""
        run "sudo chown -R \"$(whoami)\" \"$BUILD_DIR\""
        # cleanup tmp
        run "rm -rf \"$TMP_EXTRACT_DIR\" || true"
    fi

    if [[ -d "$BUILD_DIR" ]]; then
        FOUND_JAR=$(find "$BUILD_DIR" -type f \( -name 'tsk_jni.jar' -o -name 'sleuthkit-*.jar' \) 2>/dev/null | head -n1 || true)
        FOUND_SO=$(find "$BUILD_DIR" -type f -name 'libtsk_jni.so' 2>/dev/null | head -n1 || true)
        if [[ -n "$FOUND_JAR" && -n "$FOUND_SO" ]]; then
            echo "Found prebuilt JNI artifacts inside provided archive; recording as fallbacks (build will still be attempted)"
            PROVIDED_TSK_JAR="$FOUND_JAR"
            PROVIDED_TSK_SO="$FOUND_SO"
            TSK_JAR_PATH="$PROVIDED_TSK_JAR"
            TSK_SO_PATH="$PROVIDED_TSK_SO"
            # copy them into application lib now as a failsafe in case the
            # later build doesn't produce JNI artifacts.
            run "sudo mkdir -p \"$APPLICATION_INSTALL_DIR/lib\""
            run "sudo cp \"$FOUND_JAR\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
            run "sudo cp \"$FOUND_SO\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
        else
            echo "No prebuilt JNI artifacts found inside provided archive; will attempt source build unless no-build is requested"
            SKIP_BUILD=0
            # After attempting to extract archives, try a search for artifacts
            # in case the user placed prebuilt files elsewhere on the system.
            if search_for_artifacts; then
                echo "Artifacts located by search after archive extraction: $TSK_JAR_PATH and $TSK_SO_PATH"
            fi
        fi
    fi
fi

# If the user explicitly requested no-build and we still don't have artifacts, fail fast
if [[ "$NO_BUILD" -eq 1 && -z "$TSK_JAR_PATH" && -z "$TSK_SO_PATH" ]]; then
    echo "NO_BUILD set and no JNI artifacts found from .deb or provided artifacts. Failing as requested." >&2
    exit 1
fi


# Enable all repositories for apt
echo "Turning on all repositories for apt..."
if ! run "sudo sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list"; then
    echo "Failed to turn on all repositories" >>/dev/stderr
    exit 1
fi



# Pin libheif1 to required version for libheif-dev
echo "Pinning libheif1 to required version for libheif-dev..."
run "echo \"Package: libheif1\" | sudo tee /etc/apt/preferences.d/libheif1"
run "echo \"Pin: version 1.15.1-1+deb12u1\" | sudo tee -a /etc/apt/preferences.d/libheif1"
run "echo \"Pin-Priority: 1001\" | sudo tee -a /etc/apt/preferences.d/libheif1"
run "sudo apt update"
run "sudo apt-get install --allow-downgrades libheif1=1.15.1-1+deb12u1 -y"


# Install all apt dependencies (including ant for Java builds)
echo "Installing all apt dependencies..."
if ! run sudo apt-get install -y \
    build-essential autoconf libtool automake git zip wget ant ant-optional \
    libde265-dev libheif-dev \
    libpq-dev \
    testdisk libafflib-dev libewf-dev libvhdi-dev libvmdk-dev libvslvm-dev \
    libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x \
    gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio; then
    echo "Failed to install necessary dependencies" >>/dev/stderr
    exit 1
fi

# Remove Bullseye apt source after all dependencies are installed
if [ -f /etc/apt/sources.list.d/bullseye.list ]; then
    run "sudo rm /etc/apt/sources.list.d/bullseye.list"
    run "sudo apt update"
fi

echo "Autopsy prerequisites installed."

# Build and install Sleuth Kit from source if we didn't get JNI artifacts from .deb
if [[ $SKIP_BUILD -eq 0 ]]; then
    # Before attempting an expensive source build, verify we have required
    # build tools and development packages. If something is missing, print a
    # concise apt-get suggestion and fail fast so the user can choose to
    # install packages or provide prebuilt artifacts instead.
    check_build_deps() {
        MISSING_CMDS=()
        for c in gcc make autoconf automake libtool pkg-config ant javac unzip; do
            if ! command -v "$c" >/dev/null 2>&1; then
                MISSING_CMDS+=("$c")
            fi
        done

        # Packages that Sleuth Kit commonly needs for full feature set/build
        PKGS=(build-essential autoconf libtool automake git zip wget ant default-jdk libde265-dev libheif-dev libpq-dev testdisk libafflib-dev libewf-dev libvhdi-dev libvmdk-dev libvslvm-dev pkg-config zlib1g-dev)
        MISSING_PKGS=()
        for pkg in "${PKGS[@]}"; do
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                MISSING_PKGS+=("$pkg")
            fi
        done

        if [[ ${#MISSING_CMDS[@]} -eq 0 && ${#MISSING_PKGS[@]} -eq 0 ]]; then
            return 0
        fi

        echo "The system is missing build requirements for building Sleuth Kit:" >&2
        if [[ ${#MISSING_CMDS[@]} -ne 0 ]]; then
            echo " - Missing commands: ${MISSING_CMDS[*]}" >&2
        fi
        if [[ ${#MISSING_PKGS[@]} -ne 0 ]]; then
            echo " - Missing deb packages: ${MISSING_PKGS[*]}" >&2
            echo "You can install them with:" >&2
            echo "  sudo apt-get update && sudo apt-get install -y ${MISSING_PKGS[*]}" >&2
            echo "Note: openjdk-17 may require adding the Bullseye repository on older Debian releases (script previously adds it)." >&2
        fi
        return 1
    }

    echo "Preparing to build Sleuth Kit from source..."
    if ! check_build_deps; then
        echo "Aborting source build due to missing build dependencies." >&2
        exit 1
    fi
    cd "$BUILD_DIR" || { echo "$BUILD_DIR directory missing"; exit 1; }
    make clean || true
    ./bootstrap
    ./configure --enable-java
    make
    cd bindings/java/jni || { echo "Failed to enter bindings/java/jni"; exit 1; }
    ant
    cd ../../../.. || { echo "Failed to return from jni dir"; exit 1; }
    run "sudo make install"
else
    echo "Not building Sleuth Kit from source (deb used)"
fi

# Install or copy tsk_jni.jar and libtsk_jni.so into Autopsy lib directory
run "sudo mkdir -p \"$APPLICATION_INSTALL_DIR/lib\""
# Prefer built artifacts if present
if [[ -f "$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar" ]]; then
    echo "Copying built jar into application lib"
    run "sudo cp \"$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
    TSK_JAR_PATH="$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar"
fi
if [[ -f "$BUILD_DIR/bindings/java/jni/.libs/libtsk_jni.so" ]]; then
    echo "Copying built shared lib into application lib"
    run "sudo cp \"$BUILD_DIR/bindings/java/jni/.libs/libtsk_jni.so\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
    TSK_SO_PATH="$BUILD_DIR/bindings/java/jni/.libs/libtsk_jni.so"
fi

# If built artifacts weren't produced, use provided / package / common locations
if [[ -z "$TSK_JAR_PATH" || -z "$TSK_SO_PATH" ]]; then
    echo "Built artifacts not found (or incomplete). Using provided/package fallbacks if available."
    if [[ -n "$PROVIDED_TSK_JAR" && -f "$PROVIDED_TSK_JAR" ]]; then
        run "sudo cp \"$PROVIDED_TSK_JAR\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
        TSK_JAR_PATH="$PROVIDED_TSK_JAR"
    fi
    if [[ -n "$PROVIDED_TSK_SO" && -f "$PROVIDED_TSK_SO" ]]; then
        run "sudo cp \"$PROVIDED_TSK_SO\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
        TSK_SO_PATH="$PROVIDED_TSK_SO"
    fi

    # Try package-provided paths via dpkg
    if [[ -z "$TSK_JAR_PATH" ]]; then
        PKG_JAR=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 -E 'tsk_jni.jar|sleuthkit-.*\.jar' || true)
        if [[ -n "$PKG_JAR" ]]; then
            run "sudo cp \"$PKG_JAR\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
            TSK_JAR_PATH="$PKG_JAR"
        fi
    fi
    if [[ -z "$TSK_SO_PATH" ]]; then
        PKG_SO_PATH=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'libtsk_jni.so' || true)
        if [[ -n "$PKG_SO_PATH" ]]; then
            run "sudo cp \"$PKG_SO_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
            TSK_SO_PATH="$PKG_SO_PATH"
        fi
    fi

    # Final fallback: common library directories
    if [[ -z "$TSK_SO_PATH" ]]; then
        for _p in /usr/lib/x86_64-linux-gnu/libtsk_jni.so /usr/lib/libtsk_jni.so /usr/local/lib/libtsk_jni.so; do
            if [[ -f "$_p" ]]; then
                run "sudo cp \"$_p\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
                TSK_SO_PATH="$_p"
                break
            fi
        done
    fi
fi
APPLICATION_NAME="${APPLICATION_NAME:-autopsy}"
APPLICATION_ZIP_PATH="${APPLICATION_ZIP_PATH:-$AUTOPSY_DL_PATH}"
INSTALL_DIR="${INSTALL_DIR:-/usr/lib}"
APPLICATION_INSTALL_DIR="${APPLICATION_INSTALL_DIR:-${INSTALL_DIR}/${APPLICATION_NAME}-4.22.0}"
JAVA_PATH="${JAVA_PATH:-/usr/lib/jvm/java-17-openjdk-amd64}"

# Extract Autopsy zip into a temporary directory, then move its contents into
# APPLICATION_INSTALL_DIR to avoid double-nested directories (e.g., .../autopsy-4.22.0/autopsy-4.22.0).
echo "Preparing to extract Autopsy into $APPLICATION_INSTALL_DIR"
# Backup existing installation if it exists and is non-empty
BACKUP_DIR=""
if [[ -d "$APPLICATION_INSTALL_DIR" && -n "$(ls -A "$APPLICATION_INSTALL_DIR" 2>/dev/null)" ]]; then
    BACKUP_DIR="${APPLICATION_INSTALL_DIR}.backup.$(date +%s)"
    echo "Backing up existing installation to $BACKUP_DIR"
    run "sudo mv \"$APPLICATION_INSTALL_DIR\" \"$BACKUP_DIR\""
fi

# Ensure target exists
run "sudo mkdir -p \"$APPLICATION_INSTALL_DIR\""

echo "Unpacking Autopsy zip directly into $APPLICATION_INSTALL_DIR"
if run "sudo unzip -o \"$APPLICATION_ZIP_PATH\" -d \"$APPLICATION_INSTALL_DIR\""; then
    echo "Unpack succeeded; setting ownership"
    run "sudo chown -R \"$(whoami)\" \"$APPLICATION_INSTALL_DIR\" || true"
    # Remove backup if present
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        echo "Removing backup at $BACKUP_DIR"
        run "sudo rm -rf \"$BACKUP_DIR\" || true"
    fi
else
    echo "ERROR: Unpacking Autopsy zip failed. Restoring previous installation if available." >&2
    # Remove possibly partially-extracted dir
    run "sudo rm -rf \"$APPLICATION_INSTALL_DIR\" || true"
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        echo "Restoring backup from $BACKUP_DIR"
        run "sudo mv \"$BACKUP_DIR\" \"$APPLICATION_INSTALL_DIR\" || true"
    fi
    exit 1
fi

APPLICATION_EXTRACTED_PATH="$APPLICATION_INSTALL_DIR"

echo "Setting up application at $APPLICATION_EXTRACTED_PATH..."
UNIX_SETUP_PATH=$(find "$APPLICATION_EXTRACTED_PATH" -maxdepth 2 -name 'unix_setup.sh' | head -n1 | xargs -I{} dirname {})
if [[ -z "$UNIX_SETUP_PATH" ]]; then
    echo "Could not find unix_setup.sh in $APPLICATION_EXTRACTED_PATH" >>/dev/stderr
    exit 1
fi
    # Prefer copying the sleuthkit jar into the Autopsy lib directory instead
    # of creating a persistent system-level symlink.  This keeps system
    # footprint smaller while ensuring unix_setup.sh can find the expected
    # jar name during setup. If unix_setup.sh still requires a /usr/share/java
    # path, create a temporary symlink that will be removed after setup.
    TMP_SYS_JAR_LINK_CREATED=0
    # Prefer system-installed jar, but also check the BUILD_DIR (if we built or moved source there)
    FOUND_JAR=$(ls /usr/share/java/sleuthkit-*.jar 2>/dev/null | head -n1 || true)
    if [[ -z "$FOUND_JAR" && -f "$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar" ]]; then
        FOUND_JAR="$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar"
    fi
    if [[ -z "$FOUND_JAR" ]]; then
        FOUND_JAR=$(ls "$BUILD_DIR"/sleuthkit-*.jar 2>/dev/null | head -n1 || true)
    fi
    if [[ -n "$FOUND_JAR" ]]; then
        echo "Copying sleuthkit jar into application lib: $FOUND_JAR -> $APPLICATION_INSTALL_DIR/lib/"
        sudo mkdir -p "$APPLICATION_INSTALL_DIR/lib"
        DEST_JAR="$APPLICATION_INSTALL_DIR/lib/$(basename "$FOUND_JAR")"
        run "sudo cp \"$FOUND_JAR\" \"$DEST_JAR\" || true"
        # Also ensure a jar with the legacy name exists inside the app lib so
        # post-install checks and runtime lookups are happy.
        LEGACY_NAME="$APPLICATION_INSTALL_DIR/lib/sleuthkit-4.13.0.jar"
        if [[ ! -f "$LEGACY_NAME" ]]; then
            run "sudo cp \"$DEST_JAR\" \"$LEGACY_NAME\" || true"
        fi
        # Create a temporary system symlink only if unix_setup.sh needs the
        # jar under /usr/share/java. We'll point it at the copy in the app
        # lib and remove it afterwards to avoid persistent system changes.
        if [[ ! -e "/usr/share/java/sleuthkit-4.13.0.jar" ]]; then
            echo "Creating temporary system symlink so unix_setup.sh can find sleuthkit jar"
            run "sudo ln -sfn \"$DEST_JAR\" /usr/share/java/sleuthkit-4.13.0.jar"
            TMP_SYS_JAR_LINK_CREATED=1
        fi
    fi

    # Make sure the system linker cache knows about any newly-installed JNI libs
    # (dpkg usually installs them into /usr/lib/x86_64-linux-gnu). This helps
    # runtime lookups that unix_setup.sh or Autopsy may perform.
    run "sudo ldconfig || true"
    pushd "$UNIX_SETUP_PATH" || { echo "Failed to change to $UNIX_SETUP_PATH"; exit 1; }
    # Ensure we can change ownership and permissions even when files are owned by root
    run "sudo chown -R \"$(whoami)\" \"$UNIX_SETUP_PATH\""
    run "sudo chmod u+x \"$UNIX_SETUP_PATH/unix_setup.sh\""
    # Run the unix_setup.sh as the current user (ownership has been changed above)
    if ! run "\"$UNIX_SETUP_PATH/unix_setup.sh\" -j \"$JAVA_PATH\" -n \"$APPLICATION_NAME\""; then
        popd || true
        echo "Unable to setup permissions for application binaries" >>/dev/stderr
        exit 1
    fi
    popd || true

    # Continue with post-install actions
    # Ensure all files have Unix line endings (quiet)
    run "sudo apt-get install -y dos2unix"
    # Use find + xargs with nulls to quiet dos2unix output and skip binaries
    run "sudo find \"$APPLICATION_INSTALL_DIR\" -type f -print0 | sudo xargs -0 -r dos2unix >/dev/null 2>&1 || true"
    # Convert Autopsy launcher script to LF line endings
    if [ -f "$UNIX_SETUP_PATH/bin/autopsy" ]; then
        run "sudo dos2unix \"$UNIX_SETUP_PATH/bin/autopsy\""
    fi

    # Create compatibility symlink /usr/autopsy -> $APPLICATION_INSTALL_DIR
    TARGET_LINK="/usr/autopsy"
    if [ -L "$TARGET_LINK" ]; then
        run "sudo ln -sfn \"$APPLICATION_INSTALL_DIR\" \"$TARGET_LINK\""
    elif [ -e "$TARGET_LINK" ]; then
        BACKUP_PATH="${TARGET_LINK}.backup.$(date +%s)"
        run "sudo mv \"$TARGET_LINK\" \"$BACKUP_PATH\""
        run "sudo ln -s \"$APPLICATION_INSTALL_DIR\" \"$TARGET_LINK\""
        echo "Existing $TARGET_LINK moved to $BACKUP_PATH and symlink created."
    else
        run "sudo ln -s \"$APPLICATION_INSTALL_DIR\" \"$TARGET_LINK\""
    fi

    # Finalization: cleanup, recovery, and smoke-check
    # ---------------------------------------------
    # This section performs the final tidy-up and verification after
    # running `unix_setup.sh`.  It has three responsibilities:
    #  1) Remove a temporary system-level symlink the installer may have
    #     created in /usr/share/java so `unix_setup.sh` can find a jar.
    #     The symlink is removed only if it points at a path we created
    #     or discovered (DEST_JAR or TSK_JAR_PATH) to avoid touching
    #     unrelated system symlinks.
    #  2) Ensure the application `lib/` directory contains both the
    #     Sleuth Kit jar and the JNI shared object. If either is missing
    #     we attempt to copy them from discovered locations or the
    #     installed `sleuthkit-java` package.
    #  3) Fail fast with a clear error if required artifacts are still
    #     missing; this avoids leaving a broken Autopsy installation.
    #
    # Note: this block intentionally focuses on safety and idempotence —
    # it attempts recovery when reasonable and cleans only the symlink
    # it created.
    
    # Remove temporary system sleuthkit jar symlink if we created it and it
    # points to our application copy. This avoids leaving persistent symlinks
    # in /usr/share/java.  Compare against both DEST_JAR (the copy we created)
    # and TSK_JAR_PATH (any discovered jar path) so we don't remove unrelated
    # symlinks.
    if [[ "$TMP_SYS_JAR_LINK_CREATED" -eq 1 ]]; then
        if [[ -L "/usr/share/java/sleuthkit-4.13.0.jar" ]]; then
            TARGET=$(readlink -f /usr/share/java/sleuthkit-4.13.0.jar || true)
            MATCH=0
            if [[ -n "$DEST_JAR" && -n "$TARGET" ]]; then
                if [[ "$TARGET" = "$(readlink -f "$DEST_JAR" 2>/dev/null)" ]]; then
                    MATCH=1
                fi
            fi
            if [[ "$MATCH" -eq 0 && -n "$TSK_JAR_PATH" && -n "$TARGET" ]]; then
                if [[ "$TARGET" = "$(readlink -f "$TSK_JAR_PATH" 2>/dev/null)" ]]; then
                    MATCH=1
                fi
            fi
            if [[ "$MATCH" -eq 1 ]]; then
                run "sudo rm -f /usr/share/java/sleuthkit-4.13.0.jar || true"
            fi
        fi
    fi

    # Smoke-check: verify sleuthkit jar and JNI .so are present inside the
    # application lib directory. If missing, attempt to copy them from
    # discovered paths (TSK_JAR_PATH / TSK_SO_PATH) or the installed package
    # before failing. This reduces false negatives during idempotent runs.
    echo "Verifying presence of sleuthkit jar and libtsk_jni.so in $APPLICATION_INSTALL_DIR/lib"
    HAS_JAR=0
    HAS_SO=0

    if ls "$APPLICATION_INSTALL_DIR/lib/"*sleuthkit*.jar >/dev/null 2>&1 || [ -f "$APPLICATION_INSTALL_DIR/lib/tsk_jni.jar" ]; then
        HAS_JAR=1
    fi
    if [ -f "$APPLICATION_INSTALL_DIR/lib/libtsk_jni.so" ]; then
        HAS_SO=1
    fi

    # Try to copy missing artifacts from known/discovered locations
    if [[ "$HAS_JAR" -ne 1 ]]; then
        # Before giving up, run the search routine to find artifacts the
        # user may have placed elsewhere on disk.
        if search_for_artifacts; then
            echo "Artifacts discovered by search during finalization: $TSK_JAR_PATH"
        fi
        if [[ -n "$TSK_JAR_PATH" && -f "$TSK_JAR_PATH" ]]; then
            echo "Copying discovered jar $TSK_JAR_PATH into application lib"
            run "sudo cp \"$TSK_JAR_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
            HAS_JAR=1
        else
            # Prefer BUILD_DIR artifacts (if present), then package-provided jars
            if [[ -f "$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar" ]]; then
                echo "Copying built jar from $BUILD_DIR into application lib"
                run "sudo cp \"$BUILD_DIR/bindings/java/jni/dist/tsk_jni.jar\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
                HAS_JAR=1
            else
                PKG_JAR=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 -E 'tsk_jni.jar|sleuthkit-.*\.jar' || true)
                if [[ -n "$PKG_JAR" && -f "$PKG_JAR" ]]; then
                    echo "Copying package-provided jar $PKG_JAR into application lib"
                    run "sudo cp \"$PKG_JAR\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
                    HAS_JAR=1
                fi
            fi
        fi
    fi

    if [[ "$HAS_SO" -ne 1 ]]; then
        if [[ -n "$TSK_SO_PATH" && -f "$TSK_SO_PATH" ]]; then
            echo "Copying discovered shared lib $TSK_SO_PATH into application lib"
            run "sudo cp \"$TSK_SO_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
            HAS_SO=1
        else
            # Prefer BUILD_DIR shared lib, then package-provided path
            if [[ -f "$BUILD_DIR/bindings/java/jni/.libs/libtsk_jni.so" ]]; then
                echo "Copying built shared lib from $BUILD_DIR into application lib"
                run "sudo cp \"$BUILD_DIR/bindings/java/jni/.libs/libtsk_jni.so\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
                HAS_SO=1
            else
                PKG_SO_PATH=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'libtsk_jni.so' || true)
                if [[ -n "$PKG_SO_PATH" && -f "$PKG_SO_PATH" ]]; then
                    echo "Copying package-provided shared lib $PKG_SO_PATH into application lib"
                    run "sudo cp \"$PKG_SO_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
                    HAS_SO=1
                fi
            fi
        fi
    fi

    if [[ "$HAS_JAR" -ne 1 || "$HAS_SO" -ne 1 ]]; then
        echo "ERROR: Required Sleuth Kit artifacts missing in $APPLICATION_INSTALL_DIR/lib" >&2
        if [[ "$HAS_JAR" -ne 1 ]]; then echo " - Missing jar: expected sleuthkit-*.jar or tsk_jni.jar" >&2; fi
        if [[ "$HAS_SO" -ne 1 ]]; then echo " - Missing shared lib: libtsk_jni.so" >&2; fi
        exit 1
    fi

    # Cleanup any leftover backup directories created during the unpack phase
    # (pattern: <install_dir>.backup.<timestamp>)
    shopt -s nullglob
    for b in "${APPLICATION_INSTALL_DIR}.backup."*; do
        if [[ -d "$b" ]]; then
            echo "Removing leftover backup directory: $b"
            run "sudo rm -rf \"$b\" || true"
        fi
    done
    shopt -u nullglob

    echo "Application setup done.  You can run $APPLICATION_NAME from $UNIX_SETUP_PATH/bin/$APPLICATION_NAME."