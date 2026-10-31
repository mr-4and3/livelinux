#!/bin/bash


set_update() {
    local CHROOT_DIR="$1"
    local PACKAGE_LIST="${2:-}"

    if [ ! -d "$CHROOT_DIR" ]; then
        echo "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    # Update package lists and upgrade packages in the chroot environment
    sudo chroot "$CHROOT_DIR" /bin/bash -e -c '
        export DEBIAN_FRONTEND=noninteractive
        echo "Updating package lists and upgrading packages in chroot environment..."
        apt-get update
        echo "Upgrading packages..."
        apt-get upgrade -y
    '

    # Install additional packages if specified
    if [ -n "$PACKAGE_LIST" ]; then
        for package in $PACKAGE_LIST; do
            sudo chroot "$CHROOT_DIR" /bin/bash -e -c "
                export DEBIAN_FRONTEND=noninteractive
                echo \"Installing package: $package\"
                apt-get install -y $package
            "
        done
    fi
    
    # Clean up package lists to reduce the size of the chroot environment
    sudo chroot "$CHROOT_DIR" /bin/bash -e -c '
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    '
}