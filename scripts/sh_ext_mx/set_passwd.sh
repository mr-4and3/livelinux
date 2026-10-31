#!/bin/bash

set_passwd() {
    local CHROOT_DIR="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../common.sh"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi
 
    sudo chroot "$CHROOT_DIR" passwd demo
}