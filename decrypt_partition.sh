#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/sda2}"
MAPPING="${2:-usbdata}"
MOUNTPOINT="${3:-/mnt/usbdata}"

if [[ ! -b "$DEVICE" ]]; then
    echo "[!] Gerät nicht gefunden: $DEVICE" >&2
    exit 1
fi

if ! command -v tcplay >/dev/null 2>&1; then
    echo "[!] tcplay ist nicht installiert. Bitte zuerst installieren:" >&2
    echo "    sudo apt update && sudo apt install -y tcplay" >&2
    exit 1
fi

if [[ -b "/dev/mapper/$MAPPING" ]]; then
    echo "[*] $MAPPING is already mapped in /dev/mapper/$MAPPING."
else
    echo "[*] Please enter the password for $DEVICE:"
    sudo tcplay -m "$MAPPING" -d "$DEVICE"
fi

sudo mkdir -p "$MOUNTPOINT"
if mountpoint -q "$MOUNTPOINT"; then
    echo "[*] $MOUNTPOINT is already mounted. Unmounting it safely first..."
    sudo umount "$MOUNTPOINT" || true
fi

sudo mount -o rw,uid=0,gid=0,umask=0000 /dev/mapper/$MAPPING "$MOUNTPOINT"
sudo chmod 0777 "$MOUNTPOINT"
sudo chmod -R a+rwX "$MOUNTPOINT"

echo "[*] Access via $MOUNTPOINT"
echo "[*] Everyone can now read and write to this mount."
echo "[*] To close:"
echo "    sudo umount '$MOUNTPOINT'"
echo "    sudo tcplay -u '$MAPPING'"
