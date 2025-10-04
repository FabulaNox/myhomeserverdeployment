#!/bin/bash
# This script installs the Autopsy application on a Linux system.

wget https://github.com/sleuthkit/sleuthkit/releases/download/sleuthkit-4.14.0/sleuthkit-java_4.14.0-1_amd64.deb
wget https://github.com/sleuthkit/autopsy/releases/download/autopsy-4.22.1/autopsy-4.22.1.zip
echo "deb http://deb.debian.org/debian bullseye main" | sudo tee /etc/apt/sources.list.d/bullseye.list
sudo apt update
sudo apt install -t bullseye openjdk-17-jdk openjdk-17-jre -y
sudo rm /etc/apt/sources.list.d/bullseye.list
sudo apt update
# this script is designed to install necessary dependencies on debian
# this script requires elevated privileges

echo "Turning on all repositories for apt..."
sudo sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
if [[ $? -ne 0 ]]; then
    echo "Failed to turn on all repositories" >>/dev/stderr
    exit 1
fi

echo "Installing all apt dependencies..."
sudo apt update && \
    sudo apt -y install \
        build-essential autoconf libtool automake git zip wget ant \
        libde265-dev libheif-dev \
        libpq-dev \
        testdisk libafflib-dev libewf-dev libvhdi-dev libvmdk-dev libvslvm-dev \
        libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x \
        gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio

if [[ $? -ne 0 ]]; then
    echo "Failed to install necessary dependencies" >>/dev/stderr
    exit 1
fi

echo "Autopsy prerequisites installed."
echo "Java 17 instllation: "
update-java-alternatives -l | grep java-1.17
sudo dpkg -i sleuthkit-java_4.14.0-1_amd64.deb
sudo apt -f install -y
# Unzips an application platform zip to specified directory and does setup

usage() {
    echo "Usage: install_application.sh [-z zip_path] [-i install_directory] [-j java_home] [-n application_name] [-v asc_file]" 1>&2
    echo "If specifying a .asc verification file (with -v flag), the program will attempt to create a temp folder in the working directory and verify the signature with gpg.  If you already have an extracted zip, the '-z' flag can be ignored as long as the directory specifying the extracted contents is provided for the installation directory." 1>&2
}

APPLICATION_NAME="autopsy";

while getopts "n:z:i:j:v:" o; do
    case "${o}" in
    n)
        APPLICATION_NAME=${OPTARG}
        ;;
    z)
        APPLICATION_ZIP_PATH=${OPTARG}
        ;;
    i)
        INSTALL_DIR=${OPTARG}
        ;;
    v)
        ASC_FILE=${OPTARG}
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

# If zip path has not been specified and there is nothing at the install directory
if [[ -z "$APPLICATION_ZIP_PATH" ]] && [[ ! -d "$INSTALL_DIR" ]]; then
    usage
    exit 1
fi

# check against the asc file if the zip exists
if [[ -n "$ASC_FILE" ]] && [[ -n "$APPLICATION_ZIP_PATH" ]]; then
    VERIFY_DIR=$(pwd)/temp
    KEY_DIR=$VERIFY_DIR/private
    mkdir -p $VERIFY_DIR &&
        sudo wget -O $VERIFY_DIR/carrier.asc https://sleuthkit.org/carrier.asc &&
        mkdir -p $KEY_DIR &&
        sudo chmod 600 $KEY_DIR &&
        sudo gpg --homedir "$KEY_DIR" --import $VERIFY_DIR/carrier.asc &&
        sudo gpgv --homedir "$KEY_DIR" --keyring "$KEY_DIR/pubring.kbx" $ASC_FILE $APPLICATION_ZIP_PATH &&
        sudo rm -r $VERIFY_DIR
    if [[ $? -ne 0 ]]; then
        echo "Unable to successfully verify $APPLICATION_ZIP_PATH with $ASC_FILE" >>/dev/stderr
        exit 1
    fi
fi

APPLICATION_EXTRACTED_PATH=$INSTALL_DIR/

# if specifying a zip path, ensure directory doesn't exist and then create and extract
if [[ -n "$APPLICATION_ZIP_PATH" ]]; then
    if [[ -f $APPLICATION_EXTRACTED_PATH ]]; then
        echo "A file already exists at $APPLICATION_EXTRACTED_PATH" >>/dev/stderr
        exit 1
    fi

    echo "Extracting $APPLICATION_ZIP_PATH to $APPLICATION_EXTRACTED_PATH..."
    mkdir -p $APPLICATION_EXTRACTED_PATH &&
        unzip $APPLICATION_ZIP_PATH -d $INSTALL_DIR
    if [[ $? -ne 0 ]]; then
        echo "Unable to successfully extract $APPLICATION_ZIP_PATH to $INSTALL_DIR" >>/dev/stderr
        exit 1
    fi
fi 

echo "Setting up application at $APPLICATION_EXTRACTED_PATH..."
# find unix_setup.sh in least nested path (https://stackoverflow.com/a/40039568/2375948)
UNIX_SETUP_PATH=`find $APPLICATION_EXTRACTED_PATH -maxdepth 2 -name 'unix_setup.sh' | head -n1 | xargs -I{} dirname {}`

pushd $UNIX_SETUP_PATH &&
    chown -R $(whoami) . &&
    chmod u+x ./unix_setup.sh &&
    ./unix_setup.sh -j $JAVA_PATH -n $APPLICATION_NAME &&
    popd
if [[ $? -ne 0 ]]; then
    echo "Unable to setup permissions for application binaries" >>/dev/stderr
    exit 1
else
    echo "Application setup done.  You can run $APPLICATION_NAME from $UNIX_SETUP_PATH/bin/$APPLICATION_NAME."
fi