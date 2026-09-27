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

# source the lightdm configuration setting script
LIGHTDM_CONF_SCRIPT="$SCRIPT_DIR/set_lightdm_conf.sh"
if [ -f "$LIGHTDM_CONF_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$LIGHTDM_CONF_SCRIPT"
else
    error "Missing lightdm configuration setting script: $LIGHTDM_CONF_SCRIPT" >&2
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

# source the tor browser setting script
TOR_BROWSER_SCRIPT="$SCRIPT_DIR/set_torbrowser.sh"
if [ -f "$TOR_BROWSER_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$TOR_BROWSER_SCRIPT"
else
    error "Missing tor browser setting script: $TOR_BROWSER_SCRIPT" >&2
    exit 1
fi

DESKTOP_SCRIPT="$SCRIPT_DIR/set_desktop.sh"
if [ -f "$DESKTOP_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$DESKTOP_SCRIPT"
else
    error "Missing desktop setting script: $DESKTOP_SCRIPT" >&2
    exit 1
fi

DEB_SCRIPT="$SCRIPT_DIR/set_deb.sh"
if [ -f "$DEB_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$DEB_SCRIPT"
else
    error "Missing deb setting script: $DEB_SCRIPT" >&2
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
    set_lightdm_conf "$CHROOT_DIR"
    set_decrypt_script "$CHROOT_DIR" 
    set_usb_live_mount "$CHROOT_DIR"
    set_update "$CHROOT_DIR" "exfat-fuse exfatprogs ntfs-3g dmsetup xdotool tcplay torbrowser-launcher zenity"
    
    # remove the mx-wel*.desktop files to avoid the welcome screen
    sudo find "$CHROOT_DIR" \
        \( -path "$CHROOT_DIR/proc" -o -path "$CHROOT_DIR/sys" -o -path "$CHROOT_DIR/dev" -o -path "$CHROOT_DIR/run" \) -prune -o \
        -type f -name "mx-wel*.desktop" -exec rm -f {} +

    # remove the minstall.desktop file to avoid the installer
    sudo find "$CHROOT_DIR" \
        \( -path "$CHROOT_DIR/proc" -o -path "$CHROOT_DIR/sys" -o -path "$CHROOT_DIR/dev" -o -path "$CHROOT_DIR/run" \) -prune -o \
        -type f -name "minstall.desktop" -exec rm -f {} +
             
    #set_torbrowser "$CHROOT_DIR"
    set_desktop "$CHROOT_DIR" \
    "tor-browser.desktop" \
    "torbrowser-launcher" \
    "Script for opening the Tor Browser" \
    "/usr/local/bin/torbrowser-launcher.sh" \
    "/usr/share/icons/Papirus/64x64/apps/tor-browser.svg"
    #set_deb "$CHROOT_DIR" "https://github.com/veracrypt/VeraCrypt/releases/download/VeraCrypt_1.26.29/veracrypt-1.26.29-Debian-13-amd64.deb"
}
