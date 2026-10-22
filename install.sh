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

set -u

source "$(dirname "$0")/common.sh"

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

    ensure_sudo "$@"

    install_package "rsync" "rsync"
    install_package "xorriso" "xorriso"
    install_package "squashfs-tools" "unsquashfs"
    install_package "tcplay" "tcplay"
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
    install_package "syslinux" "syslinux"
    install_package "zenity" "zenity"
    install_package "virt-viewer" "virt-viewer"
    install_package "gpg" "gpg"

    local username="${SUDO_USER:-$USER}"
    sudo usermod -aG kvm "$username"

    # Check if the user is in the kvm group
    if ! groups "$username" | grep -q '\bkvm\b'; then
        error "User $username is not in the 'kvm' group. Please log out and log back in for the group change to take effect."
    fi  
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_install "$@"
fi
