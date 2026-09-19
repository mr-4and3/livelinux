#!/bin/bash

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
    if [ ! -f /usr/share/ovmf/OVMF.fd ]; then
        echo "OVMF.fd not found, please install the ovmf package first."
        exit
    fi

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

    # Boot the target USB device as a USB storage stick, closer to real hardware.
    sudo qemu-system-x86_64 \
        -enable-kvm \
        -m 4096 \
        -vga qxl \
        -bios /usr/share/ovmf/OVMF.fd \
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

