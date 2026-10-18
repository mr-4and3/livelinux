#!/bin/bash
# Copyright (c) 2026 mr_4and3
#
# This file is part of livelinux.
# It is licensed under the MIT License.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# For more information, see the MIT License: https://opensource.org/licenses/MIT


source "$(dirname "$0")/common.sh"

# Script usage information
usage() {
    echo "Usage: $0 ----usb-device <device_path>"
    echo "Example: $0 --usb-device /dev/sda"
}

# Main function to run the USB stick test   
main() {
    echo "Starting USB stick test..."
    # Add your test logic here

    ensure_sudo "$@"

    # test for installed qemu
    if ! command -v qemu-system-x86_64 &> /dev/null
    then
        echo "qemu-system-x86_64 could not be found, please install it first."
        exit
    fi

    # test for installed ovmf
    OVMF_FILE=""
    for candidate in \
        "/usr/share/ovmf/OVMF.fd" \
        "/usr/share/edk2/x64/OVMF.4m.fd" \
        "/usr/share/edk2/x64/OVMF.fd"; do
        if [ -f "$candidate" ]; then
            OVMF_FILE="$candidate"
            break
        fi
    done

    if [ -z "$OVMF_FILE" ]; then
        echo "OVMF firmware not found, please install the ovmf/edk2-ovmf package first."
        exit
    fi

    TARGET_DRIVE=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --usb-device)
                TARGET_DRIVE="$2"
                shift 2
                ;;
            --help|-h)
                usage 
                exit 0
                ;;
            *)
                error "Unknown parameter: $1"
                usage   
                exit 1
                ;;
        esac
    done

    # Check if TARGET_DRIVE is set
    if [ -z "$TARGET_DRIVE" ]; then
        error "No target drive specified."
    fi

    # Check permissions for the target drive
    if [ ! -r "$TARGET_DRIVE" ] || [ ! -w "$TARGET_DRIVE" ]; then
        warning "Insufficient permissions for the target drive: $TARGET_DRIVE."
        # check for setfacl capability
        if command -v setfacl &> /dev/null; then
            echo "Attempting to set ACL permissions for the target drive..."
            setfacl -m u:"$(whoami)":rw "$TARGET_DRIVE"
            if [ $? -ne 0 ]; then
                error "Failed to set ACL permissions for the target drive: $TARGET_DRIVE. Please run the script with appropriate permissions or as root."
                exit 1
            fi
        else
            error "setfacl command not found. Please run the script with appropriate permissions or as root."
            exit 1
        fi
    fi
        
    # Prefer a real graphical window when a desktop session exists and a GUI backend is available.
    QEMU_VGA="std"
    if qemu-system-x86_64 -device help 2>/dev/null | grep -qi qxl; then
        QEMU_VGA="qxl"
    fi

    QEMU_DISPLAY="-nographic"
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if qemu-system-x86_64 -display help 2>/dev/null | grep -qi 'gtk'; then
            QEMU_DISPLAY="-display gtk"
        elif qemu-system-x86_64 -display help 2>/dev/null | grep -qi 'sdl'; then
            QEMU_DISPLAY="-display sdl"
        else
            echo "No graphical QEMU backend available for this desktop session; falling back to console output."
        fi
    else
        echo "No desktop session detected; using console output."
    fi

    qemu-system-x86_64 \
        -enable-kvm \
        -m 4096 \
        -vga "$QEMU_VGA" \
        $QEMU_DISPLAY \
        -bios "$OVMF_FILE" \
        -device qemu-xhci \
        -drive file="$TARGET_DRIVE",if=none,id=usb0,format=raw \
        -device usb-storage,drive=usb0 \
        -boot order=c
}

# Script error handling
error() {
    printf '\n\033[31mERROR: %s\033[0m\n\n' "$*" >&2
    usage
    exit 1
}

# Main script execution
main "$@"
