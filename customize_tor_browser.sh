#!/bin/bash

# function to customize the chroot environment
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
customize_exe() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2
    local IMAGE_DIR=$3

    sudo chroot "$CHROOT_DIR" /bin/bash -e <<EOF2
       export DEBIAN_FRONTEND=noninteractive
       apt update
       apt upgrade -y
       apt-get install -y exfat-fuse exfatprogs ntfs-3g dmsetup xdotool cryptsetup 
       apt-get install -y torbrowser-launcher 
       apt-get clean
       rm -rf /var/lib/apt/lists/*
EOF2
}
