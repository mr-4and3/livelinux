#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Bitte als root ausführen: sudo ./test_iso.sh"
    exit 1
fi

ISO="${1:-./custom-linux.iso}"

if [ ! -f "$ISO" ]; then
    echo "ISO nicht gefunden: $ISO"
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
    echo "UEFI-Firmware nicht gefunden. Bitte qemu-system-x86 und ovmf installieren."
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