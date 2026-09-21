#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYBOARD_SCRIPT="$SCRIPT_DIR/set_keyboard.sh"

source "$SCRIPT_DIR/../common.sh"

# source the keyboard setting script
if [ -f "$KEYBOARD_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$KEYBOARD_SCRIPT"
else
    error "Missing keyboard setting script: $KEYBOARD_SCRIPT"
    exit 1
fi

# source the decrypt script setting script
DECRYPT_SCRIPT="$SCRIPT_DIR/set_decrypt_script.sh"
if [ -f "$DECRYPT_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$DECRYPT_SCRIPT"
else
    error "Missing decrypt script setting script: $DECRYPT_SCRIPT" >&2
    exit 1
fi

# source the usb live mount setting script
USB_LIVE_MOUNT_SCRIPT="$SCRIPT_DIR/set_usb_live_mount.sh"
if [ -f "$USB_LIVE_MOUNT_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$USB_LIVE_MOUNT_SCRIPT"
else
    error "Missing usb live mount setting script: $USB_LIVE_MOUNT_SCRIPT" >&2
    exit 1
fi

# source the update setting script
UPDATE_SCRIPT="$SCRIPT_DIR/set_update.sh"
if [ -f "$UPDATE_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$UPDATE_SCRIPT"
else
    error "Missing update setting script: $UPDATE_SCRIPT" >&2
    exit 1
fi

# function to customize the chroot environment
# $1: CHROOT_DIR
customize_exe() {
    local CHROOT_DIR=$1

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    set_keyboard_de "$CHROOT_DIR"
    set_decrypt_script "$CHROOT_DIR" 
    set_usb_live_mount "$CHROOT_DIR"
    set_update "$CHROOT_DIR" "exfat-fuse exfatprogs ntfs-3g dmsetup xdotool tcplay torbrowser-launcher"
}
