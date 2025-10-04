#!/bin/bash

# This script is designed to install necessary dependencies on Debian, Kali, and Parrot OS
# Requires elevated privileges

echo "Adding Debian Bullseye repository for OpenJDK 17..."
echo "deb http://deb.debian.org/debian bullseye main" | sudo tee /etc/apt/sources.list.d/bullseye.list
if [[ $? -ne 0 ]]; then
    echo "Failed to add Bullseye repository" >&2
    exit 1
fi

echo "Updating apt package lists..."
sudo apt update
if [[ $? -ne 0 ]]; then
    echo "Failed to update apt package lists" >&2
    exit 1
fi

echo "Installing OpenJDK 17 from Bullseye..."
sudo apt install -y -t bullseye openjdk-17-jdk openjdk-17-jre
if [[ $? -ne 0 ]]; then
    echo "Failed to install OpenJDK 17 packages from Bullseye" >&2
    exit 1
fi

# Verify Java installation (prefer command checks, fall back to dpkg)
echo "Verifying OpenJDK 17 installation..."
if ! command -v java >/dev/null 2>&1 || ! command -v javac >/dev/null 2>&1; then
    echo "java or javac not found in PATH; checking installed packages..."
    if ! dpkg -s openjdk-17-jdk >/dev/null 2>&1 || ! dpkg -s openjdk-17-jre >/dev/null 2>&1; then
        echo "OpenJDK 17 JDK/JRE do not appear to be installed correctly." >&2
        exit 1
    fi
fi

# Remove the temporary Bullseye repository so the system isn't left using it
echo "Removing temporary Bullseye apt source to avoid pinning system to Bullseye..."
if [[ -f /etc/apt/sources.list.d/bullseye.list ]]; then
    sudo rm -f /etc/apt/sources.list.d/bullseye.list
    # Refresh package lists from the system's configured repositories
    sudo apt update || echo "Warning: apt update failed after removing bullseye.list; check your apt sources"
fi

echo "Installing other dependencies..."
sudo apt install -y build-essential autoconf libtool automake git zip unzip wget ant \
    libde265-dev libheif-dev libpq-dev \
    testdisk libafflib-dev libewf-dev libvhdi-dev libvmdk-dev libvslvm-dev \
    libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x \
    gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio
if [[ $? -ne 0 ]]; then
    echo "Failed to install other dependencies" >&2
    exit 1
fi

echo "Autopsy prerequisites installed."

# Set JAVA_HOME and update PATH
JAVA_HOME_PATH=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
if ! grep -q "export JAVA_HOME=" ~/.bashrc; then
    echo "export JAVA_HOME=$JAVA_HOME_PATH" >> ~/.bashrc
    echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> ~/.bashrc
    export JAVA_HOME=$JAVA_HOME_PATH
    export PATH=$JAVA_HOME/bin:$PATH
    echo "JAVA_HOME and PATH set in ~/.bashrc and current session."
else
    echo "JAVA_HOME already set in ~/.bashrc."
fi

echo "Java version:"
java -version

# Unzips an application platform zip to specified directory and does setup

usage() {
    echo "Usage: install_application.sh [-i install_directory] [-j java_home]" 1>&2
    echo "Automatically downloads Sleuth Kit 4.14.0 and Autopsy 4.22.1 for Kali/ParrotOS." 1>&2
}

APPLICATION_NAME="autopsy";


while getopts "i:j:" o; do
    case "${o}" in
    i)
        INSTALL_DIR=${OPTARG}
        ;;
    j)
        JAVA_PATH=${OPTARG}
        ;;
    *)
        usage
        exit 1
        ;;
    esac
done

if [[ -z "$INSTALL_DIR" ]]; then
    usage
    exit 1
fi

# Download Sleuth Kit 4.14.0
echo "Downloading Sleuth Kit 4.14.0..."
SLEUTHKIT_URL="https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-4.14.0/sleuthkit-4.14.0.tar.gz"
SLEUTHKIT_TAR="sleuthkit-4.14.0.tar.gz"
if [[ ! -f "$SLEUTHKIT_TAR" ]]; then
    if command -v curl >/dev/null 2>&1; then
        curl -L "$SLEUTHKIT_URL" -o "$SLEUTHKIT_TAR"
    else
        wget "$SLEUTHKIT_URL" -O "$SLEUTHKIT_TAR"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Failed to download Sleuth Kit." >&2
        exit 1
    fi
fi

# Download Autopsy 4.22.1
echo "Downloading Autopsy 4.22.1..."
AUTOPSY_URL="https://github.com/sleuthkit/autopsy/releases/download/autopsy-4.22.1/autopsy-4.22.1.zip"
# Use the URL basename as the desired filename so we don't accidentally mismatch names
AUTOPSY_ZIP=$(basename "$AUTOPSY_URL")
if [[ ! -f "$AUTOPSY_ZIP" ]]; then
    if command -v curl >/dev/null 2>&1; then
        curl -L --retry 5 --retry-delay 5 "$AUTOPSY_URL" -o "$AUTOPSY_ZIP"
    else
        wget --tries=5 --wait=5 -O "$AUTOPSY_ZIP" "$AUTOPSY_URL"
    fi
    if [[ $? -ne 0 ]]; then
        echo "Failed to download Autopsy." >&2
        exit 1
    fi
fi

# Extract Sleuth Kit
echo "Extracting Sleuth Kit..."
mkdir -p "$INSTALL_DIR/sleuthkit"
tar -xzf "$SLEUTHKIT_TAR" -C "$INSTALL_DIR/sleuthkit" --strip-components=1
if [[ $? -ne 0 ]]; then
    echo "Failed to extract Sleuth Kit." >&2
    exit 1
fi

# Build Sleuth Kit
echo "Building Sleuth Kit..."
pushd "$INSTALL_DIR/sleuthkit"
./configure && make && sudo make install
if [[ $? -ne 0 ]]; then
    echo "Failed to build/install Sleuth Kit." >&2
    exit 1
fi
popd

# Extract Autopsy
echo "Extracting Autopsy..."
mkdir -p "$INSTALL_DIR/autopsy"

# Ensure unzip is available (some minimal Debian installs may not have it)
if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip not found, installing unzip..."
    sudo apt update && sudo apt install -y unzip
fi

# Test the zip archive before extracting
if ! unzip -t "$AUTOPSY_ZIP" >/dev/null 2>&1; then
    echo "Downloaded Autopsy zip appears corrupt or invalid." >&2
    exit 1
fi

# Extract, overwriting if necessary
unzip -o "$AUTOPSY_ZIP" -d "$INSTALL_DIR/autopsy"
if [[ $? -ne 0 ]]; then
    echo "Failed to extract Autopsy." >&2
    exit 1
fi

# Find unix_setup.sh and run it (search recursively)
UNIX_SETUP_PATH=$(find "$INSTALL_DIR/autopsy" -name 'unix_setup.sh' | head -n1 | xargs -I{} dirname {})
if [[ -z "$UNIX_SETUP_PATH" ]]; then
    echo "Could not find unix_setup.sh in $INSTALL_DIR/autopsy" >&2
    exit 1
fi

pushd "$UNIX_SETUP_PATH"
# Use SUDO_USER if running under sudo so files belong to the real user
OWNER="$(whoami)"
if [[ -n "$SUDO_USER" ]]; then
    OWNER="$SUDO_USER"
fi
chown -R "$OWNER" .
chmod u+x ./unix_setup.sh
./unix_setup.sh -j "$JAVA_PATH" -n "$APPLICATION_NAME"
popd

if [[ $? -ne 0 ]]; then
    echo "Unable to setup permissions for application binaries" >&2
    exit 1
else
    echo "Application setup done. You can run $APPLICATION_NAME from $UNIX_SETUP_PATH/bin/$APPLICATION_NAME."
fi