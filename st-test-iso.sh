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

set -e

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS] [ISO_PATH]

Start a custom Linux ISO in QEMU with UEFI support.

Arguments:
  ISO_PATH                 ISO image to boot (default: ./custom-linux.iso)

Options:
  --iso PATH               ISO image to boot (alternative to ISO_PATH)
  --qemu-mode MODE         QEMU mode: static or dynamic (default: static)
  --ovmf PATH              UEFI firmware file (auto-detected by default)
  --omf PATH               Alias for --ovmf
  -h, --help               Show this help message

The script switches to the kvm group when needed. The user must already be
a member of that group to use KVM acceleration.

Examples:
  ${0##*/} ./custom-linux.iso
  ${0##*/} --iso ./custom-linux.iso --qemu-mode dynamic
  ${0##*/} --ovmf /path/to/OVMF.fd ./custom-linux.iso
EOF
}

# This script is designed to run a custom Linux ISO in a QEMU virtual machine with UEFI support.
main() {
    # Default ISO path
    local ISO="custom-linux.iso"
    local QEMU_MODE="static"
    local QEMU_ARGS=()
    local OVMF_FILE=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --iso)
                ISO="$2"
                shift 2
                ;;
            --qemu-mode)
                QEMU_MODE="$2"
                shift 2
                ;;
            --ovmf|--omf)
                OVMF_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                ISO="$1"
                shift
                ;;
        esac
    done

    # Check if the ISO file exists
    if [ ! -f "$ISO" ]; then
        error "ISO not found: $ISO"
        exit 1
    fi

    if [ -z "$OVMF_FILE" ]; then
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
    fi

    if [ "$QEMU_MODE" == "static" ]; then
        run_qemu_static "$ISO" "$OVMF_FILE"
    else
        run_qemu_dynamic "$ISO" "$OVMF_FILE"
    fi
}

run_qemu_dynamic() {
    local ISO="$1"
    local OVMF_FILE="$2"

    QEMU_ARGS=(
        -m 4G
        -enable-kvm
        -vga virtio
        -spice "port=5930,disable-ticketing=on"
        -device virtio-serial-pci
        -device "virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
        -chardev "spicevmc,id=spicechannel0,name=vdagent"
        -display spice-app
        -bios "$OVMF_FILE"
        -cdrom "$ISO"
        -boot d
    )

    exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
}

run_qemu_static() {
    local ISO="$1"
    local OVMF_FILE="$2"

    QEMU_ARGS=(
        -m 4G
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
}

ensure_kvm_group() {
    local current_uid
    current_uid=$(id -u)

    if [ "$current_uid" -ne 0 ] && ! id -Gn | tr ' ' '\n' | grep -Fxq kvm; then
        if [ "${LIVELINUX_KVM_REEXEC:-0}" = 1 ]; then
            error "Failed to switch to the 'kvm' group."
            exit 1
        fi

        local username
        username=$(id -un)
        if ! getent group kvm | awk -F: -v user="$username" '
            {
                count = split($4, members, ",")
                for (i = 1; i <= count; i++) {
                    if (members[i] == user) {
                        found = 1
                    }
                }
            }
            END { exit !found }
        '; then
            error "User '$username' is not a member of the 'kvm' group."
            exit 1
        fi

        local script_path reexec_command argument
        script_path="$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
        reexec_command="LIVELINUX_KVM_REEXEC=1 exec bash $(quote_shell_argument "$script_path")"
        for argument in "$@"; do
            reexec_command+=" $(quote_shell_argument "$argument")"
        done
        exec newgrp kvm -c "$reexec_command"
    fi

    if [ "$current_uid" -ne 0 ] && { [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; }; then
        error "The 'kvm' group is active, but /dev/kvm is not readable and writable by this user."
        exit 1
    fi
}

# Start of the script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_kvm_group "$@"
    main "$@"
fi