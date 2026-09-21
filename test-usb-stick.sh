#!/bin/bash

source "$(dirname "$0")/install.sh"

main() {
    echo "Starting USB stick test..."
    # Add your test logic here

    # test for being run as root
    if [ "$EUID" -ne 0 ]
    then
        echo "Please run as root"
        exit
    fi

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

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --usb-device)
                TARGET_DRIVE="$2"
                shift 2
                ;;
            --install)
                install_package "qemu-system-x86" "qemu-system-x86_64"
                install_package "qemu-system-gui" "qemu-system-gui"
                install_package "edk2-ovmf" "" "/usr/share/edk2/x64/OVMF.4m.fd"
                shift
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

    sudo qemu-system-x86_64 \
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


# Script usage information
usage() {
    echo "Usage: $0 --stick_device <device_path>"
    echo "Example: $0 --stick_device /dev/sda"
}

# Script error handling
error() {
    printf '\n\033[31mERROR: %s\033[0m\n\n' "$*" >&2
    usage
    exit 1
}

# Main script execution
main "$@"

