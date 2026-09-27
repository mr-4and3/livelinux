#!/bin/bash

# function to print warning messages in yellow
warning() {
    printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2
    logger -t livelinux "WARNING: $*"
}

debug() {
    printf '\033[36mDEBUG: %s\033[0m\n' "$*" >&2
    logger -t livelinux "DEBUG: $*"
}

error() {
    local message="${1:-unknown error}"
    local caller_script="${BASH_SOURCE[1]:-${0}}"
    local caller_line="${BASH_LINENO[0]:-0}"

    printf '\n\033[31mERROR: %s\033[0m\n' "$message " >&2
    printf '\033[31m  in %s:%s\033[0m\n\n' "$caller_script" "$caller_line" >&2
    logger -t livelinux "ERROR: $message in $caller_script:$caller_line"
}

success() {
    printf '\033[32mSUCCESS: %s\033[0m\n' "$*" >&2
    logger -t livelinux "SUCCESS: $*"
}

# Exit on any error and propagate ERR traps into functions
error_handler() {
    local exit_code=$?
    local caller_script="${BASH_SOURCE[1]:-${0}}"
    local caller_line="${BASH_LINENO[0]:-0}"

    printf '\033[31mERROR: command failed with exit code %d: %s\033[0m\n' \
        "$exit_code" "$BASH_COMMAND" >&2
    printf '  in %s:%s\n' "$caller_script" "$caller_line" >&2
    logger -t livelinux "ERROR: command failed with exit code $exit_code: $BASH_COMMAND in $caller_script:$caller_line"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root. Please use sudo."
        exit 1
    fi
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

    if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        local sudo_pass="$(zenity --password --title="sudo" --text="Bitte sudo-Passwort eingeben:" 2>/dev/null || true)"
        if [[ -z "$sudo_pass" ]]; then
            printf '%s\n' "sudo password cancelled." >&2
            exit 1
        fi
        printf '%s\n' "$sudo_pass" | sudo -S -v >/dev/null 2>&1 || {
            printf '%s\n' "sudo authentication failed." >&2
            exit 1
        }
        return 0
    fi

    local sudo_pass=""
    read -r -s -p "sudo Passwort: " sudo_pass
    printf '\n'
    printf '%s\n' "$sudo_pass" | sudo -S -v >/dev/null 2>&1 || {
        printf '%s\n' "sudo authentication failed." >&2
        exit 1
    }
}


header() {
    printf "* %s\n" "$*" >&2
}
