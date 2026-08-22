#!/bin/bash
# Script for creating a customized MX-Linux image via chroot

# Exit on any error and propagate ERR traps into functions
set -eE

# Functions
##############################################################################
error_handler() {
    local exit_code=$?
    printf '\033[31mERROR: command failed with exit code %d: %s\033[0m\n' \
        "$exit_code" "$BASH_COMMAND" >&2
}

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

# function to unmount chroot mounts
unmount_chroot_mounts() {
    for mountpoint in "$CHROOT_DIR/sys" "$CHROOT_DIR/proc" "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev"; do
        if mountpoint -q "$mountpoint"; then
            sudo umount "$mountpoint" 2>/dev/null || sudo umount -l "$mountpoint"
        fi
    done
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

# function to ensure work directories exist
ensure_workdirs() {
    mkdir -p "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
}

# function to check if chroot mounts are ready
chroot_mounts_ready() {
    local mountpoint

    for mountpoint in \
        "$CHROOT_DIR/dev" \
        "$CHROOT_DIR/dev/pts" \
        "$CHROOT_DIR/proc" \
        "$CHROOT_DIR/sys"; do

        if ! mountpoint -q "$mountpoint"; then
            return 1
        fi
    done

    return 0
}

system_check() {
    if ! command -v sudo &> /dev/null; then
        echo "[!] sudo not found. Please install it first."
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        echo "[!] Please run the script with sudo!"
        exit 1
    fi

    if ! command -v rsync &> /dev/null; then
        echo "[!] rsync not found. Please install it first."
        exit 1
    fi

    if ! command -v xorriso &> /dev/null; then
        echo "[!] xorriso not found. Please install it first."
        exit 1
    fi

    if ! command -v unsquashfs &> /dev/null; then
        echo "[!] unsquashfs not found. Please install squashfs-tools first."
        exit 1
    fi
}

system_prepare() {
    echo "=== System preparation ==="
    sudo apt-get update
    sudo apt-get install -y squashfs-tools xorriso rsync
}

clean() {
    echo "=== Cleaning up work directory ==="
    if [ -d "$WORK_DIR" ]; then
        warning "Work directory $WORK_DIR already exists. It will be deleted."
        read -p "Do you want to continue? (y/n): " choice
        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            echo "Cancelled."
            exit 1
        fi
        cleanup_workdir
        sudo rm -rf "$WORK_DIR"
    fi
}

prepare() {
    echo "=== 1. Prepare, install tools ==="
    clean
    ensure_workdirs
    system_prepare
}

linuxfs() {
    echo "=== 2. Mount MX Linux ISO and extract files ==="
    ensure_workdirs
    mkdir -p "$MNT_DIR"
    sudo mount -o loop "$ISO_SRC" "$MNT_DIR"
    rsync -a --exclude=/antiX/linuxfs "$MNT_DIR/" "$IMAGE_DIR/"
    sudo unsquashfs -d "$CHROOT_DIR" "$MNT_DIR/antiX/linuxfs"
    sudo umount "$MNT_DIR"
}

mount_for_chroot() {
    echo "=== 3. Mounting chroot directories ==="
    ensure_workdirs

    mountpoint -q "$CHROOT_DIR/dev" || \
        sudo mount --bind /dev "$CHROOT_DIR/dev"
    mountpoint -q "$CHROOT_DIR/dev/pts" || \
        sudo mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
    mountpoint -q "$CHROOT_DIR/proc" || \
        sudo mount --bind /proc "$CHROOT_DIR/proc"
    mountpoint -q "$CHROOT_DIR/sys" || \
        sudo mount --bind /sys "$CHROOT_DIR/sys"

    sudo cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"
}

customize() {
    echo "=== 4. Execute customizations in MX-Chroot ==="
    ensure_workdirs
    
    if ! chroot_mounts_ready; then
        mount_for_chroot
    else
        echo "Chroot mounts already exist."
    fi

    sudo chroot "$CHROOT_DIR" /bin/bash -e <<EOF2
       export DEBIAN_FRONTEND=noninteractive
       apt-get update
       apt-get install -y exfat-fuse exfatprogs ntfs-3g dmsetup xdotool cryptsetup tor
       apt-get clean
       rm -rf /var/lib/apt/lists/*
EOF2
}

new_mx_squashfs() {
    echo "=== 5. Clean up chroot and create new MX-SquashFS ==="
    unmount_chroot_mounts
    mkdir -p "$IMAGE_DIR/antiX"
    sudo rm -f "$IMAGE_DIR/antiX/linuxfs"
    sudo mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/antiX/linuxfs" -comp xz
    (cd "$IMAGE_DIR/antiX" && md5sum linuxfs > linuxfs.md5)
}

create_final_iso() {
    echo "=== 6. Create final hybrid-bootable MX-ISO ==="
    xorriso -as mkisofs -r -V "Custom_MX" \
        -o "$WORK_DIR/custom-mx-linux.iso" \
        -J -joliet-long -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat -no-emul-boot \
        -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        "$IMAGE_DIR"
    echo "=== DONE! Your MX image is located at: $WORK_DIR/custom-mx-linux.iso ==="
}

shell() {
    echo "=== Interactive shell inside MX-Chroot ==="
    ensure_workdirs

    if ! chroot_mounts_ready; then
        mount_for_chroot
    else
        echo "Chroot mounts already exist."
    fi

    sudo chroot "$CHROOT_DIR" /bin/bash
}

# Script starts here
##############################################################################

# Default values
ISO_SRC="/home/fsteinha/Downloads/MX-25_Xfce_x64.iso"
WORK_DIR="./mx-work"
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
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"
MNT_DIR="$WORK_DIR/mnt"

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
        linuxfs
        ;;
    customize)
        customize
        ;;
    shell)
        shell
        ;;
    new_mx_squashfs)
        new_mx_squashfs
        ;;
    create_final_iso)
        create_final_iso
        ;;
    all)
        prepare
        linuxfs
        customize
        new_mx_squashfs
        create_final_iso
        ;;
    *)
        echo "Unknown step: $STEP"
        usage
        exit 1
        ;;
esac
