#!/bin/bash


set_deb() {
    CHROOT_DIR=$1
    DEB_URL=$2
    DEB_NAME=$(basename "$DEB_URL")
    DOWNLOAD_DIR="./download/${DEB_NAME%.*}"

    
    # 1. Benötigte Verzeichnisse erstellen
    rm -rf $DOWNLOAD_DIR/
    mkdir -p $DOWNLOAD_DIR/

    curl -LO --output-dir $DOWNLOAD_DIR/ $DEB_URL
    chmod +x "$CHROOT_DIR/usr/bin/tor-browser"
    
    DEB_FILE=$(realpath "$DOWNLOAD_DIR/$DEB_NAME")
    
    sudo chroot "$CHROOT_DIR" /bin/bash -e -c "
        dpkg -i '$DEB_FILE'
    "   
}

# Run the function if the script is executed directly
if [ "$0" = "$BASH_SOURCE" ]; then
    if [ $# -ne 1 ]; then
        echo "Usage: $0 <chroot_directory>"
        exit 1
    fi

    CHROOT_DIR=$1
    set_deb "$CHROOT_DIR" "$2"  
fi