#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    printf '%s\n' "Run this script as your regular user, without sudo." >&2
    exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
    package_manager="apt"
elif command -v pacman >/dev/null 2>&1; then
    package_manager="pacman"
else
    printf '%s\n' "This configure script requires apt-get (Debian-based) or pacman (Arch-based)." >&2
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "sudo is required to install system packages." >&2
    exit 1
fi

if [[ "$package_manager" == "apt" ]]; then
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        ca-certificates \
        curl \
        git \
        libgl1-mesa-dev \
        libwayland-dev \
        libx11-dev \
        libxcb-render0-dev \
        libxcb-shape0-dev \
        libxcb-xfixes0-dev \
        libxcursor-dev \
        libxi-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev \
        libxrandr-dev \
        pkg-config
else
    sudo pacman -S --needed --noconfirm \
        base-devel \
        ca-certificates \
        curl \
        git \
        libglvnd \
        libx11 \
        libxcb \
        libxcursor \
        libxi \
        libxkbcommon \
        libxkbcommon-x11 \
        libxrandr \
        mesa \
        pkgconf \
        wayland
fi

export PATH="$HOME/.cargo/bin:$PATH"

if ! command -v rustup >/dev/null 2>&1; then
    rustup_installer="$(mktemp)"
    trap 'rm -f "$rustup_installer"' EXIT
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$rustup_installer"
    sh "$rustup_installer" -y --profile minimal --default-toolchain stable
fi

rustup toolchain install stable --profile minimal
rustup default stable

printf '\n%s\n' "Rust build environment is ready."
printf '%s\n' "Build the GUI with: cargo build --manifest-path safe-stick/Cargo.toml"
