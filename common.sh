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
    printf '\n\033[31mERROR: %s\033[0m\n\n' "$*" >&2 
    logger -t livelinux "ERROR: $*"
}

success() {
    printf '\033[32mSUCCESS: %s\033[0m\n' "$*" >&2
    logger -t livelinux "SUCCESS: $*"
}

# Exit on any error and propagate ERR traps into functions
error_handler() {
    local exit_code=$?
    printf '\033[31mERROR: command failed with exit code %d: %s\033[0m\n' \
        "$exit_code" "$BASH_COMMAND" >&2
    logger -t livelinux "ERROR: command failed with exit code $exit_code: $BASH_COMMAND"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root. Please use sudo."
        exit 1
    fi
}

header() {
    printf "* %s\n" "$*" >&2
}
