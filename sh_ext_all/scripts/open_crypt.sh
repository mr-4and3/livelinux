#!/usr/bin/env bash

# set -euo pipefail for better error handling
set -euo pipefail

# This script is used to open an encrypted volume using tcplay and mount it to a specified mount point.
# Usage: ./open_crypt.sh [DEVICE] [MAPPING] [MOUNTPOINT]
# DEVICE: The block device to open (default: /dev/sda2)
# MAPPING: The name to use for the mapped device (default: usbdata)
# MOUNTPOINT: The directory to mount the decrypted volume (default: /mnt/usbdata)
main() {
    local DEVICE="${1:-/dev/sda2}"
    local MAPPING="${2:-usbdata}"
    local MOUNTPOINT="${3:-/mnt/usbdata}"

    if [[ "$(id -u)" -ne 0 ]]; then
        ensure_sudo
    fi

    if [[ ! -b "$DEVICE" ]]; then
        message "error" "Device not found: $DEVICE"
        exit 1
    fi

    local TCPLAY_BIN
    TCPLAY_BIN="$(resolve_tcplay_bin)" || {
        message "error" "tcplay is not installed. Please install it first"
        exit 1
    }

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

    sudo mount -o rw,uid=0,gid=0,umask=0000 /dev/mapper/$MAPPING "$MOUNTPOINT"
    sudo chmod 0777 "$MOUNTPOINT"
    sudo chmod -R a+rwX "$MOUNTPOINT"

    message "notification" "[*] Creating close_crypt.sh script in home directory..."
    cat > "$HOME/close_crypt.sh" <<EOL
#!/usr/bin/env bash
sudo umount '$MOUNTPOINT'
sudo "$TCPLAY_BIN" -u '$MAPPING'
EOL

    chmod +x "$HOME/close_crypt.sh"

    message "info" "[*] Access via $MOUNTPOINT
[*] Everyone can now read and write to this mount.
[*] To close:
    sudo umount '$MOUNTPOINT'
    sudo "$TCPLAY_BIN" -u '$MAPPING'
[*] Or run the script $HOME/close_crypt.sh to unmount and close the encrypted device."
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
        local sudo_pass="$(zenity --password --title="sudo" --text="Bitte sudo-Passwort eingeben:" 2>/dev/null || true)"
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