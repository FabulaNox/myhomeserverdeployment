#!/bin/bash
# This script installs the Autopsy application on a Linux system.

# Download required packages (Sleuth Kit 4.12.0)

# Install prerequisites
sudo apt-get update
sudo apt-get install -y build-essential autoconf libtool automake git zip wget ant ant-optional openjdk-17-jdk openjdk-17-jre

# Download required packages (Sleuth Kit 4.13.0)
wget https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-4.13.0/sleuthkit-4.13.0.tar.gz
wget https://github.com/sleuthkit/autopsy/releases/download/autopsy-4.22.0/autopsy-4.22.0.zip

# Install Java 17 from Bullseye
echo "deb http://deb.debian.org/debian bullseye main" | sudo tee /etc/apt/sources.list.d/bullseye.list > /dev/null
if ! grep -q "deb http://deb.debian.org/debian bullseye main" /etc/apt/sources.list.d/bullseye.list; then
    echo "Failed to add Bullseye apt source" >&2
    exit 1
fi
sudo apt update
sudo apt install -t bullseye openjdk-17-jdk openjdk-17-jre -y
update-java-alternatives -l | grep java-1.17




# Extract Sleuth Kit tarball
echo "Extracting Sleuth Kit tarball..."
tar -xzf sleuthkit-4.13.0.tar.gz


# Enable all repositories for apt
echo "Turning on all repositories for apt..."
sudo sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
if [[ $? -ne 0 ]]; then
    echo "Failed to turn on all repositories" >>/dev/stderr
    exit 1
fi



# Pin libheif1 to required version for libheif-dev
echo "Pinning libheif1 to required version for libheif-dev..."
echo "Package: libheif1" | sudo tee /etc/apt/preferences.d/libheif1
echo "Pin: version 1.15.1-1+deb12u1" | sudo tee -a /etc/apt/preferences.d/libheif1
echo "Pin-Priority: 1001" | sudo tee -a /etc/apt/preferences.d/libheif1
sudo apt update
sudo apt-get install libheif1=1.15.1-1+deb12u1 -y


# Install all apt dependencies (including ant for Java builds)
echo "Installing all apt dependencies..."
sudo apt-get install -y \
    build-essential autoconf libtool automake git zip wget ant ant-optional \
    libde265-dev libheif-dev \
    libpq-dev \
    testdisk libafflib-dev libewf-dev libvhdi-dev libvmdk-dev libvslvm-dev \
    libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x \
    gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio


# Remove Bullseye apt source after all dependencies are installed
if [ -f /etc/apt/sources.list.d/bullseye.list ]; then
    sudo rm /etc/apt/sources.list.d/bullseye.list
    sudo apt update
fi

if [[ $? -ne 0 ]]; then
    echo "Failed to install necessary dependencies" >>/dev/stderr
    exit 1
fi

echo "Autopsy prerequisites installed."

# Build and install Sleuth Kit from source
echo "Building and installing Sleuth Kit..."
cd sleuthkit-4.13.0
make clean
./bootstrap
./configure --enable-java
make
cd bindings/java/jni
ant
cd ../../../..
sudo make install

# Install locally built tsk_jni.jar (Sleuth Kit 4.12.0)
sudo mkdir -p /usr/autopsy/autopsy-4.22.0/lib
sudo cp sleuthkit-4.13.0/bindings/java/jni/dist/tsk_jni.jar /usr/autopsy/autopsy-4.22.0/lib/
# Copy built libtsk_jni.so to Autopsy lib directory
sudo cp sleuthkit-4.13.0/bindings/java/jni/.libs/libtsk_jni.so /usr/autopsy/autopsy-4.22.0/lib/
usage() {
    echo "Usage: install_application.sh [-z zip_path] [-i install_directory] [-j java_home] [-n application_name]" 1>&2
}

APPLICATION_NAME="autopsy"
APPLICATION_ZIP_PATH="${HOME}/Downloads/autopsy-4.22.0.zip"
INSTALL_DIR="/usr/autopsy"
JAVA_PATH="/usr/lib/jvm/java-17-openjdk-amd64"

while getopts "n:z:i:j:" o; do
    case "${o}" in
    n) APPLICATION_NAME=${OPTARG} ;;
    z) APPLICATION_ZIP_PATH=${OPTARG} ;;
    i) INSTALL_DIR=${OPTARG} ;;
    j) JAVA_PATH=${OPTARG} ;;
    *) usage; exit 1 ;;
    esac
done

# Extract Autopsy zip to install directory
APPLICATION_EXTRACTED_PATH="$INSTALL_DIR"
sudo mkdir -p "$APPLICATION_EXTRACTED_PATH"
sudo unzip "$APPLICATION_ZIP_PATH" -d "$APPLICATION_EXTRACTED_PATH"

echo "Setting up application at $APPLICATION_EXTRACTED_PATH..."
UNIX_SETUP_PATH=$(find "$APPLICATION_EXTRACTED_PATH" -maxdepth 2 -name 'unix_setup.sh' | head -n1 | xargs -I{} dirname {})
if [[ -z "$UNIX_SETUP_PATH" ]]; then
    echo "Could not find unix_setup.sh in $APPLICATION_EXTRACTED_PATH" >>/dev/stderr
    exit 1
fi
pushd "$UNIX_SETUP_PATH"
chown -R $(whoami) .
chmod u+x ./unix_setup.sh
./unix_setup.sh -j "$JAVA_PATH" -n "$APPLICATION_NAME"
popd
if [[ $? -ne 0 ]]; then
    echo "Unable to setup permissions for application binaries" >>/dev/stderr
    exit 1
else
    # Ensure all files have Unix line endings
    sudo apt-get install dos2unix -y
    sudo find /usr/autopsy -type f -exec dos2unix {} +
    # Convert Autopsy launcher script to LF line endings
    if [ -f "$UNIX_SETUP_PATH/bin/autopsy" ]; then
        sudo dos2unix "$UNIX_SETUP_PATH/bin/autopsy"
    fi
    echo "Application setup done.  You can run $APPLICATION_NAME from $UNIX_SETUP_PATH/bin/$APPLICATION_NAME."
fi