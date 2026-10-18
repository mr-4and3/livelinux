#!/bin/bash
set -e

source "$(dirname "$0")/common.sh"

# login in kvm group
if ! groups | grep -q '\bkvm\b'; then
    newgrp kvm
    if [ $? -ne 0 ]; then
        error "Failed to switch to 'kvm' group. Please ensure you have the necessary permissions."
        exit 1
    fi  
fi

# Allow root or a user with access to KVM.
if ! groups | grep -q '\bkvm\b' && [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root or by a user in the 'kvm' group."
    exit 1
fi
#check_root

ISO="${1:-./custom-linux.iso}"

if [ ! -f "$ISO" ]; then
    error "ISO not found: $ISO"
    exit 1
fi

OVMF_FILE=""
for candidate in \
    "/usr/share/ovmf/OVMF.fd" \
    "/usr/share/edk2/x64/OVMF.4m.fd" \
    "/usr/share/edk2/x64/OVMF.fd" \
    "/usr/share/OVMF/OVMF_CODE.fd"; do
    if [ -f "$candidate" ]; then
        OVMF_FILE="$candidate"
        break
    fi
done

if [ -z "$OVMF_FILE" ]; then
    error "UEFI-Firmware nicht gefunden. Bitte qemu-system-x86 und ovmf installieren."
    exit 1
fi

QEMU_ARGS=(
    -m 4096
    -enable-kvm
    -vga std
    -bios "$OVMF_FILE"
    -cdrom "$ISO"
    -boot d
)

if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if qemu-system-x86_64 -display help 2>/dev/null | grep -qi gtk; then
        QEMU_ARGS+=(-display gtk)
    elif qemu-system-x86_64 -display help 2>/dev/null | grep -qi sdl; then
        QEMU_ARGS+=(-display sdl)
    else
        QEMU_ARGS+=(-nographic)
    fi
else
    QEMU_ARGS+=(-nographic)
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"