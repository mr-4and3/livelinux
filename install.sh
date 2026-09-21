#!/bin/bash

set -u

install_package() {
    local package_name="$1"
    local check_command="${2:-$package_name}"
    local check_path="${3:-}"

    if command -v "$check_command" >/dev/null 2>&1 || [[ -n "$check_path" && -e "$check_path" ]]; then
        echo "$package_name is already installed."
        return 0
    fi

    echo "$package_name is not installed. Installing..."

    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "$package_name"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "$package_name"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$package_name"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$package_name"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm "$package_name"
    else
        echo "No supported package manager found. Please install $package_name manually."
        exit 1
    fi
}

install_syslinux() {
    if command -v apt-get >/dev/null 2>&1; then
        install_package "syslinux" "syslinux"
    elif command -v yum >/dev/null 2>&1; then
        install_package "syslinux" "syslinux"
    elif command -v dnf >/dev/null 2>&1; then
        install_package "syslinux" "syslinux"
    elif command -v zypper >/dev/null 2>&1; then
        install_package "syslinux" "syslinux"
    elif command -v pacman >/dev/null 2>&1; then
        install_package "syslinux" "syslinux"
    else
        echo "Please install the 'syslinux' package manually for your distro."
    fi
}

main_install() {
    install_package "rsync" "rsync"
    install_package "xorriso" "xorriso"
    install_package "squashfs-tools" "unsquashfs"
    install_package "veracrypt" "veracrypt"
    install_package "util-linux" "lsblk"
    install_package "parted" "parted"
    install_package "coreutils" "dd"
    install_package "qemu-system-x86" "qemu-system-x86_64"
    install_package "qemu-desktop" "qemu-system-x86_64"
    install_package "edk2-ovmf" "" "/usr/share/edk2/x64/OVMF.4m.fd"
    install_package "ovmf" "" "/usr/share/OVMF/OVMF_CODE.fd"
    if command -v pacman >/dev/null 2>&1; then
        install_package "ovmf" "" "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
    fi
    install_syslinux
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_install "$@"
fi
