#!/bin/bash


set_keyboard_de() {
    local CHROOT_DIR="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../common.sh"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    sudo mkdir -p "$CHROOT_DIR/etc/X11/xorg.conf.d"

    # keyboard configuration file
    ##########################################################################
    if [ ! -f "$SCRIPT_DIR/config/keyboard" ]; then
        error "Missing keyboard configuration file: $SCRIPT_DIR/config/keyboard" >&2
        return 1
    fi
    
    # copy the keyboard configuration file to the chroot environment
    sudo cp "$SCRIPT_DIR/config/keyboard" "$CHROOT_DIR/etc/default/keyboard"
    
    # vconsole configuration file
    ##########################################################################
    if [ ! -f "$SCRIPT_DIR/config/vconsole.conf" ]; then
        error "Missing vconsole configuration file: $SCRIPT_DIR/config/vconsole.conf" >&2
        return 1
    fi

    # copy the vconsole configuration file to the chroot environment
    sudo cp "$SCRIPT_DIR/config/vconsole.conf" "$CHROOT_DIR/etc/vconsole.conf"

    # xorg keyboard configuration file
    ##########################################################################
    if [ ! -f "$SCRIPT_DIR/config/00-keyboard.conf" ]; then
        error "Missing xorg keyboard configuration file: $SCRIPT_DIR/config/00-keyboard.conf" >&2
        return 1
    fi

    # copy the xorg keyboard configuration file to the chroot environment
    sudo cp "$SCRIPT_DIR/config/00-keyboard.conf" "$CHROOT_DIR/etc/X11/xorg.conf.d/00-keyboard.conf"

    # set the keyboard layout in the chroot environment
    sudo chroot "$CHROOT_DIR" /bin/bash -e <<'EOF'
export DEBIAN_FRONTEND=noninteractive

if command -v dpkg-reconfigure >/dev/null 2>&1; then
    dpkg-reconfigure -f noninteractive keyboard-configuration >/dev/null 2>&1 || true
fi

if command -v localectl >/dev/null 2>&1; then
    localectl set-x11-keymap de pc105 nodeadkeys >/dev/null 2>&1 || true
fi

if command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap de pc105 nodeadkeys >/dev/null 2>&1 || true
fi
EOF
}