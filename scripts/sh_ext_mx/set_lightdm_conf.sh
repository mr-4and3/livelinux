#!/bin/bash


set_lightdm_conf() {
    local CHROOT_DIR="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../common.sh"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    # lightdm configuration file
    ##########################################################################
    if [ ! -f "$SCRIPT_DIR/config/lightdm.conf" ]; then
        error "Missing lightdm configuration file: $SCRIPT_DIR/config/lightdm.conf" >&2
        return 1
    fi

    # save the lightdm configuration file to the chroot environment
    sudo cp "$CHROOT_DIR/etc/lightdm/lightdm.conf" "$CHROOT_DIR/etc/lightdm/lightdm.conf.bak" 2>/dev/null || true

    # copy the lightdm configuration file to the chroot environment
    sudo cp "$SCRIPT_DIR/config/lightdm.conf" "$CHROOT_DIR/etc/lightdm/lightdm.conf"      
}