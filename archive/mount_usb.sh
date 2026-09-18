# Set script to exit immediately if any command fails
set -eE

# include common functions and variables
source common.sh

TARGET_DRIVE="" # WIRD UNTEN ABGEFRAGT (z.B. /dev/sdb)
WORK_DIR="$(pwd)"
WORK_DIR="$(realpath -m "$WORK_DIR")"
MOUNT_DIR="$WORK_DIR/mnt_usb"
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"


usage() {
    cat <<EOF
Usage: $0 [--target-drive <path>] [--help]
Options:
  --target-drive <path>  Specify the target USB stick (e.g., /dev/sdb)
    mount                  Mount the selected partition at ./mnt_usb
    extract                Extract antiX/linuxfs into ./chroot
    shell                  Open a shell in the extracted chroot
    unmount                Unmount ./mnt_usb
    all                    Mount and extract the selected partition
  -h, --help              Show this help message and exit
EOF
}

mount() {
    if [ -z "$TARGET_DRIVE" ]; then
        list_available_drives
    fi

    if [ ! -b "$TARGET_DRIVE" ]; then
        echo "[!] Block device not found: $TARGET_DRIVE" >&2
        exit 1
    fi

    mkdir -p "$MOUNT_DIR"

    existing_mount="$(findmnt -rn -S "$TARGET_DRIVE" -o TARGET | head -n 1)"
    if [ -n "$existing_mount" ]; then
        if [ "$existing_mount" = "$MOUNT_DIR" ]; then
            echo "[*] $TARGET_DRIVE is already mounted at $MOUNT_DIR."
            return 0
        fi
        echo "[!] $TARGET_DRIVE is already mounted at $existing_mount." >&2
        echo "    Unmount it first with: sudo umount '$existing_mount'" >&2
        exit 1
    fi

    if [ "$(blkid -o value -s TYPE "$TARGET_DRIVE" 2>/dev/null)" = "iso9660" ]; then
        sudo mount -o ro "$TARGET_DRIVE" "$MOUNT_DIR"
    else
        sudo mount "$TARGET_DRIVE" "$MOUNT_DIR"
    fi

    echo "[*] Mounted $TARGET_DRIVE at $MOUNT_DIR."
}

extract() {
    local squashfs_path="$MOUNT_DIR/antiX/linuxfs"

    if ! findmnt -rn -T "$MOUNT_DIR" >/dev/null 2>&1; then
        mount
    fi

    if [ ! -f "$squashfs_path" ]; then
        echo "[!] SquashFS not found: $squashfs_path" >&2
        exit 1
    fi

    if [ -n "$(find "$WORK_DIR/chroot" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        echo "[!] Chroot is not empty: $WORK_DIR/chroot" >&2
        echo "    Remove it manually before extracting again." >&2
        exit 1
    fi

    mkdir -p "$WORK_DIR/chroot" "$WORK_DIR/image"
    rsync -a --exclude='/antiX/linuxfs' "$MOUNT_DIR/" "$WORK_DIR/image/"
    sudo unsquashfs -d "$WORK_DIR/chroot" "$squashfs_path"
    echo "[*] Extracted $squashfs_path to $WORK_DIR/chroot."
}

unmount() {
    if findmnt -rn -o TARGET | grep -Fxq "$MOUNT_DIR"; then
        sudo umount "$MOUNT_DIR"
        echo "[*] Unmounted $MOUNT_DIR."
    else
        echo "[*] Nothing is mounted at $MOUNT_DIR."
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-drive)
            if [[ $# -lt 2 ]]; then
                echo "[!] Missing value for --target-drive." >&2
                exit 1
            fi
            TARGET_DRIVE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        mount|extract|shell|unmount|all)
            POSITIONAL+=("$1")
            shift
            ;;
        *)
            echo "[!] Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Set values from positional arguments
STEP=${POSITIONAL[0]:-all}

# Trap to ensure cleanup on exit
trap error_handler ERR

case "$STEP" in
    mount)
        mount
        ;;
    extract)
        extract
        ;;
    shell)
        if [ ! -x "$CHROOT_DIR/bin/bash" ]; then
            echo "[!] Chroot not found: $CHROOT_DIR" >&2
            echo "    Run '$0 --target-drive <device> extract' first." >&2
            exit 1
        fi
        mount_for_chroot
        sudo chroot "$CHROOT_DIR" /bin/bash
        ;;
    unmount)
        unmount
        ;;
    all)
        extract
        ;;
    *)
        echo "Unknown step: $STEP"
        usage
        exit 1
        ;;
esac





