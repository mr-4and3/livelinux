#!/bin/bash

# Source common functions
source "$(dirname "$0")/common.sh"

# main function to handle command line arguments and execute the appropriate steps
main() {

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                echo "Usage: $0"
                echo "This script prepares the system for building a custom Ubuntu ISO."
                exit 0
                ;;
            \?)
                error "Invalid option: -$OPTARG"
                exit 1
                ;;
        esac
    done

    if [ "$(uname -s)" != "Linux" ]; then
        error "This script is intended to run on Linux systems only."
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" == "ubuntu" ]; then
            system_prepare_ubuntu "$@"
        else
            error "This script is intended to run on Ubuntu systems only."
            exit 1
        fi
    else
        error "Cannot determine the operating system. /etc/os-release not found."
        exit 1
    fi
}

# System preparation function to install required packages
system_prepare_ubuntu() {
    header "System preparation for Ubuntu"
    if [ "$EUID" -ne 0 ]; then
        error "Please run the script with sudo!"
        exit 1
    fi

    sudo apt-get update
    sudo apt-get install -y squashfs-tools xorriso rsync
    
    if $@; then
        success "Required packages installed."
    else
        error "Failed to install required packages."
        exit 1
    fi
}

# Script
main "$@"
