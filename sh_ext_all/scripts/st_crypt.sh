#!/bin/bash

usage() {
    echo "Usage: $0 [-d|--device <device>] [-m|--mapping <mapping>] [-p|--mountpoint <mountpoint>] [open|close]"
    echo "  -d, --device       Specify the device to open (default: partition 2 of the live USB)"
    echo "  -m, --mapping      Specify the mapping name (default: usbdata)"
    echo "  -p, --mountpoint   Specify the mount point (default: /mnt/usbdata)"
    echo "  open               Open the encrypted device"
    echo "  close              Close the encrypted device"
}

main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        ensure_sudo
    fi

    local DEVICE=""
    local MAPPING="usbdata"
    local MOUNTPOINT="/mnt/usbdata"
    local POSITIONAL=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--device)
                DEVICE="$2"
                shift 2
                ;;
            -m|--mapping)
                MAPPING="$2"
                shift 2
                ;;
            -p|--mountpoint)
                MOUNTPOINT="$2"
                shift 2
                ;;
            -h |--help)
                usage
                ;;
            open|close)
                # Handle open and close commands if needed
                POSITIONAL+=("$1")
                shift
                ;;    
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$DEVICE" ]]; then
        if ! DEVICE="$(live_usb_data_partition)"; then
            DEVICE="$(select_block_partition)" || {
                message "error" "No partition was selected or no partitions are available."
                exit 1
            }
        fi
    fi

    # Check if the device exists
    if [[ ! -b "$DEVICE" ]]; then
        message "error" "Device not found: $DEVICE"
        exit 1
    fi

    local TCPLAY_BIN
    TCPLAY_BIN="$(resolve_tcplay_bin)" || {
        message "error" "tcplay is not installed. Please install it first"
        exit 1
    }

    case "${POSITIONAL[0]}" in
        open)
            open "$DEVICE" "$MAPPING" "$MOUNTPOINT"
            ;;
        close)
            close "$MAPPING" "$MOUNTPOINT"
            ;;
        *)
            echo "Unknown positional argument: ${POSITIONAL[0]}"
            usage
            exit 1
            ;;
    esac
}

open() {
    local DEVICE="$1"
    local MAPPING="$2"
    local MOUNTPOINT="$3"

    # Check if the mapping already exists
    if [[ -b "/dev/mapper/$MAPPING" ]]; then
        message "info" "[*] $MAPPING is already mapped in /dev/mapper/$MAPPING."
    else
        prompt_for_password "$DEVICE" | sudo "$TCPLAY_BIN" -p -m "$MAPPING" -d "$DEVICE"
    fi

    sudo mkdir -p "$MOUNTPOINT"
    
    if mountpoint -q "$MOUNTPOINT"; then
        message "info" "[*] $MOUNTPOINT is already mounted. Unmounting it safely first..."
        sudo umount "$MOUNTPOINT" || true
    fi

    sudo mount -o rw,uid=0,gid=0,umask=0000 "/dev/mapper/$MAPPING" "$MOUNTPOINT"
    sudo chmod 0777 "$MOUNTPOINT"
    sudo chmod -R a+rwX "$MOUNTPOINT"
   
    message "info" "Access via $MOUNTPOINT
Everyone can now read and write to this mount."
}

close() {
    local MAPPING="$1"
    local MOUNTPOINT="$2"

    # Unmount the encrypted volume and close the mapping
    sudo umount "$MOUNTPOINT"
    sudo "$TCPLAY_BIN" -u "$MAPPING"

    # Notification of successful closure
    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        zenity "--notification" --title="Open encrypted device" --text="Encrypted device closed successfully."
    else
        printf '%s\n' "Encrypted device closed successfully." >&2
    fi
}

live_usb_data_partition() {
    local boot_source=""
    local mountpoint
    local source
    local source_type
    local disk_name
    local partition

    for mountpoint in /run/live/medium /live/boot-dev /live/medium; do
        if [[ -b "$mountpoint" ]]; then
            boot_source="$mountpoint"
            break
        fi

        boot_source="$(findmnt -rn -M "$mountpoint" -o SOURCE 2>/dev/null | head -n 1)"
        if [[ -n "$boot_source" ]]; then
            break
        fi
    done

    source="$(readlink -f "${boot_source%%\[*}")"
    if [[ -z "$source" || ! -b "$source" ]]; then
        return 1
    fi

    source_type="$(lsblk -dn -o TYPE "$source" 2>/dev/null)"
    if [[ "$source_type" == "part" ]]; then
        disk_name="$(lsblk -dn -o PKNAME "$source" 2>/dev/null)"
    elif [[ "$source_type" == "disk" ]]; then
        disk_name="$(basename "$source")"
    else
        return 1
    fi

    if [[ -z "$disk_name" ]]; then
        return 1
    fi

    partition="$(lsblk -nrpo NAME,PARTN "/dev/$disk_name" 2>/dev/null | awk '$2 == 2 { print $1; exit }')"
    if [[ -n "$partition" && -b "$partition" ]]; then
        printf '%s\n' "$partition"
        return 0
    fi

    return 1
}

select_block_partition() {
    local -a partitions
    local -a dialog_args
    local index
    local selection

    mapfile -t partitions < <(lsblk -nrpo NAME,TYPE 2>/dev/null | awk '$2 == "part" { print $1 }')
    if (( ${#partitions[@]} == 0 )); then
        return 1
    fi

    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        dialog_args=(--list --radiolist --title="Partition auswählen" --text="Bitte die gewünschte Partition auswählen:" --column="Auswahl" --column="Gerät" --print-column=2)
        for index in "${!partitions[@]}"; do
            if (( index == 0 )); then
                dialog_args+=(TRUE "${partitions[index]}")
            else
                dialog_args+=(FALSE "${partitions[index]}")
            fi
        done

        zenity "${dialog_args[@]}" 2>/dev/null
        return $?
    fi

    printf '%s\n' "Available partitions:" >&2
    for index in "${!partitions[@]}"; do
        printf '  %d) %s\n' "$((index + 1))" "${partitions[index]}" >&2
    done
    read -r -p "Select a partition by number: " selection || return 1
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#partitions[@]} )); then
        return 1
    fi

    printf '%s\n' "${partitions[selection - 1]}"
}

# Resolve the tcplay binary robustly even when launched from a desktop session with a minimal PATH.
resolve_tcplay_bin() {
    if command -v tcplay >/dev/null 2>&1; then
        command -v tcplay
        return 0
    fi

    local candidates=(
        "/usr/local/sbin/tcplay"
        "/usr/sbin/tcplay"
        "/sbin/tcplay"
        "/usr/local/bin/tcplay"
        "/usr/bin/tcplay"
        "/bin/tcplay"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

# Function to ask for sudo credentials when the script is started without sudo.
ensure_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        printf '%s\n' "sudo is not installed." >&2
        exit 1
    fi

    # If zenity is available and a graphical environment is detected, use it to prompt for the sudo password.
    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        local sudo_pass
        sudo_pass="$(zenity --password --title="sudo" --text="Bitte sudo-Passwort eingeben:" 2>/dev/null || true)"
        if [[ -z "$sudo_pass" ]]; then
            zenity --error --title="sudo" --text="sudo password cancelled." 2>/dev/null || true
            exit 1
        fi
        printf '%s\n' "$sudo_pass" | sudo -S -v >/dev/null 2>&1 || {
            zenity --error --title="sudo" --text="sudo authentication failed." 2>/dev/null || true
            exit 1
        }
        return 0
    fi
    
    # If zenity is not available, prompt for the sudo password in the terminal.
    local sudo_pass=""
    read -r -s -p "sudo Passwort: " sudo_pass
    printf '\n'
    printf '%s\n' "$sudo_pass" | sudo -S -v >/dev/null 2>&1 || {
        printf '%s\n' "sudo authentication failed." >&2
        exit 1
    }
}

# Function to read a passphrase via zenity if available, otherwise use the terminal.
# $1: Device name shown in the prompt
prompt_for_password() {
    local device="$1"

    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        if zenity --password --title="USB-Verschlüsselung" --text="Bitte Passwort für $device eingeben:" 2>/dev/null; then
            return 0
        fi
    fi

    local password=""
    read -r -s -p "Passwort für $device: " password
    printf '\n'
    printf '%s' "$password"
}

# Function to display messages using zenity if available, otherwise print to stderr
# $1: Type of message (error, info, notification)
# $2: Message text
message() {
    local type="$1"
    local text="$2"
    local caller_script="${BASH_SOURCE[1]:-${0}}"
    local caller_line="${BASH_LINENO[0]:-0}"

    if [[ "$type" == "error" ]]; then
        text="$caller_script:$caller_line: $text"
    fi

    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        zenity "--$type" --title="Open encrypted device" --text="$text"
    else
        printf '%s\n' "$text" >&2
    fi
}

# Call the main function with all script arguments
main "$@"