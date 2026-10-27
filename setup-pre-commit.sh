#!/usr/bin/env bash

set -euo pipefail

if ! command -v pre-commit >/dev/null 2>&1; then
    if [[ ! -r /etc/os-release ]]; then
        printf '%s\n' "Cannot detect the distribution: /etc/os-release is missing." >&2
        exit 1
    fi

    . /etc/os-release

    case "${ID:-}:${ID_LIKE:-}" in
        ubuntu:*|*:ubuntu*)
            if [[ "$EUID" -eq 0 ]]; then
                apt-get update
                apt-get install -y pre-commit
            else
                sudo apt-get update
                sudo apt-get install -y pre-commit
            fi
            ;;
        cachyos:*|*:arch*)
            if [[ "$EUID" -eq 0 ]]; then
                pacman -S --needed --noconfirm pre-commit
            else
                sudo pacman -S --needed --noconfirm pre-commit
            fi
            ;;
        *)
            printf 'Automatic pre-commit installation is not supported on %s.\n' "${PRETTY_NAME:-this distribution}" >&2
            printf '%s\n' "Install pre-commit with your package manager, then run this script again." >&2
            exit 1
            ;;
    esac

    if ! command -v pre-commit >/dev/null 2>&1; then
        printf '%s\n' "pre-commit installation completed, but the command is still unavailable." >&2
        exit 1
    fi
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

pre-commit install --install-hooks
pre-commit run --all-files
