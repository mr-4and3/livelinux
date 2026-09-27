#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

DESKTOP_SCRIPT="$SCRIPT_DIR/set_desktop.sh"
if [ -f "$DESKTOP_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$DESKTOP_SCRIPT"
else
    error "Missing desktop setting script: $DESKTOP_SCRIPT" >&2
    exit 1
fi


set_decrypt_script() {
    local CHROOT_DIR="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../common.sh"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    if [ ! -f "$SCRIPT_DIR/../sh_ext_all/scripts/open_crypt.sh" ]; then
        error "Missing decrypt script: $SCRIPT_DIR/open_crypt.sh"
        return 1
    fi

    sudo cp "$SCRIPT_DIR/../sh_ext_all/scripts/open_crypt.sh" "$CHROOT_DIR/usr/local/bin/open_crypt.sh"
    sudo chmod +x "$CHROOT_DIR/usr/local/bin/open_crypt.sh"

    # Create a desktop entry for the decrypt script
    set_desktop "$CHROOT_DIR" \
    "open_crypt.desktop" \
    "open_crypt" \
    "Script for opening the encrypted volume" \
    "/usr/local/bin/open_crypt.sh" \
    "/usr/share/icons/Papirus/64x64/apps/terminal.svg"
}
