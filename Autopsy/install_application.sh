#!/bin/bash
# This script installs the Autopsy application on a Linux system.

# Download required packages (Sleuth Kit 4.12.0)

# Usage function and option parsing (added: -D download-dir, -r dry-run, -v verbose)
usage() {
    echo "Usage: install_application.sh [-z zip_path] [-i install_directory] [-j java_home] [-n application_name] [-D download_dir] [-r dry-run] [-v verbose]" 1>&2
}

DRY_RUN=0
VERBOSE=0
DOWNLOAD_DIR=""

while getopts "n:z:i:j:D:rv" o; do
    case "${o}" in
    n) APPLICATION_NAME=${OPTARG} ;;
    z) APPLICATION_ZIP_PATH=${OPTARG} ;;
    i) INSTALL_DIR=${OPTARG} ;;
    j) JAVA_PATH=${OPTARG} ;;
    D) DOWNLOAD_DIR=${OPTARG} ;;
    r) DRY_RUN=1 ;;
    v) VERBOSE=1 ;;
    *) usage; exit 1 ;;
    esac
done

# Helper to run commands (supports dry-run and verbose)
run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        if [[ "$VERBOSE" -eq 1 ]]; then
            echo "[RUN] $*"
        fi
        # Use bash -c to execute the constructed command string
        cmd="$*"
        bash -c "$cmd"
    fi
}

# Default application/install locations (can be overridden with -i)
APPLICATION_NAME="${APPLICATION_NAME:-autopsy}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"
INSTALL_DIR="${INSTALL_DIR:-/usr/lib}"
APPLICATION_INSTALL_DIR="${INSTALL_DIR}/${APPLICATION_NAME}-4.22.0"

# Install prerequisites
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




# Try to install sleuthkit Java .deb first (contains JNI jar/so we need)
SKIP_BUILD=0
if [ -f "$DEB_PATH" ]; then
    echo "Installing $DEB_PATH..."
    run "sudo dpkg -i \"$DEB_PATH\" || sudo apt-get install -f -y"
    # Check if package installed and contains the JNI jar/so
    if dpkg -s sleuthkit-java 2>/dev/null | grep -q "Status:.*installed"; then
        echo "sleuthkit-java package installed via .deb"
        # try to find tsk_jni.jar and libtsk_jni.so inside the package
        TSK_JAR_PATH=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'tsk_jni.jar' || true)
        TSK_SO_PATH=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'libtsk_jni.so' || true)
        if [[ -n "$TSK_JAR_PATH" && -n "$TSK_SO_PATH" ]]; then
            echo "Found tsk_jni.jar and libtsk_jni.so in package, will copy into Autopsy lib"
            SKIP_BUILD=1
        else
            echo "Package installed but JNI artifacts not found; will fall back to building from source"
            SKIP_BUILD=0
        fi
    else
        echo "Failed to install sleuthkit-java .deb; will build from source"
        SKIP_BUILD=0
    fi
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    # Extract Sleuth Kit tarball for building
    echo "Extracting Sleuth Kit tarball from $TARBALL_PATH..."
    run "tar -xzf \"$TARBALL_PATH\""
else
    echo "Skipping source build because .deb provided required artifacts"
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
    echo "Building and installing Sleuth Kit from source..."
    cd sleuthkit-4.14.0 || { echo "sleuthkit-4.14.0 directory missing"; exit 1; }
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
if [[ "$SKIP_BUILD" -eq 1 ]]; then
    # Copy from installed package if available
    if [[ -n "$TSK_JAR_PATH" && -n "$TSK_SO_PATH" ]]; then
        run "sudo cp \"$TSK_JAR_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
        run "sudo cp \"$TSK_SO_PATH\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"
    else
        # Fallback: try locating via dpkg-list
        PKG_JAR=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'tsk_jni.jar' || true)
        PKG_SO=$(dpkg -L sleuthkit-java 2>/dev/null | grep -m1 'libtsk_jni.so' || true)
        if [[ -n "$PKG_JAR" ]]; then run "sudo cp \"$PKG_JAR\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"; fi
        if [[ -n "$PKG_SO" ]]; then run "sudo cp \"$PKG_SO\" \"$APPLICATION_INSTALL_DIR/lib/\" || true"; fi
    fi
else
    # Copy built artifacts from source build
    if [ -f sleuthkit-4.14.0/bindings/java/jni/dist/tsk_jni.jar ]; then
        run "sudo cp sleuthkit-4.14.0/bindings/java/jni/dist/tsk_jni.jar \"$APPLICATION_INSTALL_DIR/lib/\""
    fi
    if [ -f sleuthkit-4.14.0/bindings/java/jni/.libs/libtsk_jni.so ]; then
        run "sudo cp sleuthkit-4.14.0/bindings/java/jni/.libs/libtsk_jni.so \"$APPLICATION_INSTALL_DIR/lib/\""
    fi
fi
APPLICATION_NAME="${APPLICATION_NAME:-autopsy}"
APPLICATION_ZIP_PATH="${APPLICATION_ZIP_PATH:-$AUTOPSY_DL_PATH}"
INSTALL_DIR="${INSTALL_DIR:-/usr/lib}"
APPLICATION_INSTALL_DIR="${APPLICATION_INSTALL_DIR:-${INSTALL_DIR}/${APPLICATION_NAME}-4.22.0}"
JAVA_PATH="${JAVA_PATH:-/usr/lib/jvm/java-17-openjdk-amd64}"

# Extract Autopsy zip to application install directory under INSTALL_DIR
APPLICATION_EXTRACTED_PATH="$APPLICATION_INSTALL_DIR"
run "sudo mkdir -p \"$APPLICATION_EXTRACTED_PATH\""
run "sudo unzip \"$APPLICATION_ZIP_PATH\" -d \"$APPLICATION_EXTRACTED_PATH\""

echo "Setting up application at $APPLICATION_EXTRACTED_PATH..."
UNIX_SETUP_PATH=$(find "$APPLICATION_EXTRACTED_PATH" -maxdepth 2 -name 'unix_setup.sh' | head -n1 | xargs -I{} dirname {})
if [[ -z "$UNIX_SETUP_PATH" ]]; then
    echo "Could not find unix_setup.sh in $APPLICATION_EXTRACTED_PATH" >>/dev/stderr
    exit 1
fi
    # Ensure a sleuthkit jar name that Autopsy expects exists (compatibility)
    # Autopsy's installer historically looks for sleuthkit-4.13.0.jar. If the
    # system-provided package installs a newer jar (eg. sleuthkit-4.14.0.jar),
    # create a safe symlink so unix_setup.sh can find it.
    if [[ ! -e "/usr/share/java/sleuthkit-4.13.0.jar" ]]; then
        FOUND_JAR=$(ls /usr/share/java/sleuthkit-*.jar 2>/dev/null | head -n1 || true)
        if [[ -n "$FOUND_JAR" ]]; then
            echo "Creating compatibility symlink for sleuthkit jar: $FOUND_JAR -> /usr/share/java/sleuthkit-4.13.0.jar"
            run "sudo ln -sfn \"$FOUND_JAR\" /usr/share/java/sleuthkit-4.13.0.jar"
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
    # Ensure all files have Unix line endings
    run "sudo apt-get install dos2unix -y"
    run "sudo find \"$APPLICATION_INSTALL_DIR\" -type f -exec dos2unix {} +"
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

    echo "Application setup done.  You can run $APPLICATION_NAME from $UNIX_SETUP_PATH/bin/$APPLICATION_NAME."
fi