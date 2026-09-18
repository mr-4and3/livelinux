#!/bin/bash
# Script for creating a customized MX-Linux image via chroot

# include common functions and variables
source common.sh

# Exit on any error and propagate ERR traps into functions
set -eE

# Functions
##############################################################################
warning() {
    printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2
}

# function to clean up workdir and unmount any mounts
cleanup_workdir() {
    if [ -d "$WORK_DIR" ]; then
        mountpoints=$(findmnt -rn -o TARGET | awk -v base="$WORK_DIR" '$1 == base || index($1, base "/") == 1' | sort -r)
        if [ -n "$mountpoints" ]; then
            while IFS= read -r mountpoint; do
                sudo umount "$mountpoint" 2>/dev/null || sudo umount -l "$mountpoint" 2>/dev/null || true
            done <<< "$mountpoints"
        fi
    fi
}

# function to display usage information
usage() {
    cat <<EOF2
Usage: $0 [--iso <path>] [--workdir <path>] [command]

Default values:
  ISO:     /home/fsteinha/Downloads/MX-25_Xfce_x64.iso
  WORKDIR: ./mx-work

Commands:
    clean              delete the work directory after confirmation
    system_check       check required system commands
    system_prepare     install required system packages
    prepare            run clean, ensure work directories, and run system_prepare
    linuxfs            mount ISO, copy files, and uncompress linuxfs
    customize          prepare chroot and run commands inside chroot
    shell              open an interactive shell inside the chroot
    new_mx_squashfs    unmount chroot and rebuild linuxfs
    create_final_iso   create final hybrid bootable ISO
    all                run prepare, linuxfs, customize, new_mx_squashfs, and create_final_iso
EOF2
}

# Script functions
prepare() {
    echo "=== Prepare, install tools ==="
    clean
    ensure_workdirs
    system_prepare
}

# function to customize the chroot environment
# $1: CHROOT_DIR
customize() {
    CHROOT_DIR=$1
    echo "=== 3. Customize MX-Chroot ==="
    ensure_workdirs
    
    if ! chroot_mounts_ready; then
        mount_for_chroot
    else
        echo "Chroot mounts already exist."
    fi

    sudo chroot "$CHROOT_DIR" /bin/bash -e <<EOF2
       export DEBIAN_FRONTEND=noninteractive
       apt update
       apt upgrade -y
       apt-get install -y exfat-fuse exfatprogs ntfs-3g dmsetup xdotool cryptsetup 
       apt-get install -y torbrowser-launcher 
       apt-get clean
       rm -rf /var/lib/apt/lists/*
EOF2
}



# Script starts here
##############################################################################
# Default values
ISO_SRC="./MX-25_Xfce_x64.iso"
WORK_DIR="./work"
TARGET_DRIVE="" # WIRD UNTEN ABGEFRAGT (z.B. /dev/sdb)

POSITIONAL=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            ISO_SRC="$2"
            shift 2
            ;;
        --workdir)
            WORK_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        clean|system_check|system_prepare|prepare|linuxfs|customize|shell|new_mx_squashfs|create_final_iso|all)
            POSITIONAL+=("$1")
            shift
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

# Set values from positional arguments
STEP=${POSITIONAL[0]:-all}
WORK_DIR="$(realpath -m "$WORK_DIR")"
MNT_DIR="$WORK_DIR/mnt"
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"

# Trap to ensure cleanup on exit
trap error_handler ERR
trap cleanup_workdir EXIT

case "$STEP" in
    clean)
        clean
        ;;
    system_check)
        system_check
        ;;
    system_prepare)
        system_prepare
        ;;
    prepare)
        prepare
        ;;
    linuxfs)
        linuxfs $MNT_DIR $CHROOT_DIR $IMAGE_DIR
        ;;
    customize)
        customize $CHROOT_DIR
        ;;
    shell)
        shell $CHROOT_DIR
        ;;
    new_mx_squashfs)
        new_mx_squashfs $IMAGE_DIR $CHROOT_DIR
        ;;
    create_final_iso)
        create_final_iso $IMAGE_DIR $WORK_DIR
        ;;
    all)
        prepare
        linuxfs $MNT_DIR $CHROOT_DIR $IMAGE_DIR
        customize $CHROOT_DIR
        new_mx_squashfs $IMAGE_DIR $CHROOT_DIR
        create_final_iso $IMAGE_DIR $WORK_DIR
        ;;
    *)
        echo "Unknown step: $STEP"
        usage
        exit 1
        ;;
esac
