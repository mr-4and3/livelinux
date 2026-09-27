#!/bin/bash


set_update() {
    local CHROOT_DIR="$1"
    local PACKAGE_LIST="${2:-}"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ ! -d "$CHROOT_DIR" ]; then
        echo "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    if [ -n "$PACKAGE_LIST" ]; then
        sudo env PACKAGE_LIST="$PACKAGE_LIST" chroot "$CHROOT_DIR" /bin/bash -e -c '
            export DEBIAN_FRONTEND=noninteractive
            echo "Updating package lists and upgrading packages in chroot environment..."
            apt-get update
            echo "Upgrading packages..."
            apt-get upgrade -y
            echo "Installing additional packages: $PACKAGE_LIST"
            apt-get install -y $PACKAGE_LIST
            apt-get clean
            rm -rf /var/lib/apt/lists/*
        '
    else
        sudo chroot "$CHROOT_DIR" /bin/bash -e -c '
            export DEBIAN_FRONTEND=noninteractive
            echo "Updating package lists and upgrading packages in chroot environment..."
            apt-get update
            echo "Upgrading packages..."
            apt-get upgrade -y
            apt-get clean
            rm -rf /var/lib/apt/lists/*
        '
    fi
}