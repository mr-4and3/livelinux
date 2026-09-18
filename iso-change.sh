#!/bin/bash
# common.sh - Common functions for Linux ISO customization scripts

# Exit on any error and propagate ERR traps into functions
set -eE

# main function to handle command line arguments and execute the appropriate steps
main() {
    # Default values
    ISO_SRC="./MX-25_Xfce_x64.iso"
    WORK_DIR="./work"
    TARGET_DRIVE="TBD" # WIRD UNTEN ABGEFRAGT (z.B. /dev/sdb)
    WORK_DIR="$(realpath -m "$WORK_DIR")"
    MNT_DIR="$WORK_DIR/mnt"
    CHROOT_DIR="$WORK_DIR/chroot"
    IMAGE_DIR="$WORK_DIR/image"
    ISO_OUTPUT="./custom-linux.iso"

    POSITIONAL=()

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --iso-input)
                ISO_SRC="$2"
                shift 2
                ;;
            --workdir)
                WORK_DIR="$2"
                shift 2
                ;;
            --iso-output)
                ISO_OUTPUT="$2"
                shift 2
                ;;
            --help|-h)
                usage $ISO_SRC $WORK_DIR $TARGET_DRIVE $MNT_DIR $CHROOT_DIR $IMAGE_DIR $ISO_OUTPUT
                exit 0
                ;;                
            clean|system_check|system_prepare|prepare|extract|customize|shell|make_iso|all)
                POSITIONAL+=("$1")
                shift
                ;;
            *)
                error "Unknown parameter: $1"
                usage $ISO_SRC $WORK_DIR $TARGET_DRIVE $MNT_DIR $CHROOT_DIR $IMAGE_DIR $ISO_OUTPUT
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

    for STEP in "${POSITIONAL[@]}"; do
        case "$STEP" in
            clean)
                clean "$WORK_DIR"
                ;;
            system_check)
                system_check
                ;;
            system_prepare)
                system_prepare
                ;;
            prepare)
                prepare "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
                ;;
            extract)
                linuxfs "$WORK_DIR" "$MNT_DIR" "$ISO_SRC" "$IMAGE_DIR"
                ;;
            customize)
                customize "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
                ;;
            shell)
                shell "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
                ;;
            make_iso)
                new_mx_squashfs "$IMAGE_DIR" "$CHROOT_DIR"
                create_final_iso "$WORK_DIR" "$IMAGE_DIR"
                ;;
            all)
                prepare "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
                linuxfs "$WORK_DIR" "$MNT_DIR" "$ISO_SRC" "$IMAGE_DIR"
                customize "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
                new_mx_squashfs "$IMAGE_DIR" "$CHROOT_DIR"
                create_final_iso "$WORK_DIR" "$IMAGE_DIR"
                ;;
            *)
                echo "Unknown step: $STEP"
                usage $ISO_SRC $WORK_DIR $TARGET_DRIVE $MNT_DIR $CHROOT_DIR $IMAGE_DIR $ISO_OUTPUT
                exit 1
                ;;
        esac
    done
}

# Helper Functions
##############################################################################

# function to print warning messages in yellow
warning() {
    printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2
}

error() {
    printf '\n\033[31mERROR: %s\033[0m\n\n' "$*" >&2
}

success() {
    printf '\033[32mSUCCESS: %s\033[0m\n' "$*" >&2
}

# Exit on any error and propagate ERR traps into functions
error_handler() {
    local exit_code=$?
    printf '\033[31mERROR: command failed with exit code %d: %s\033[0m\n' \
        "$exit_code" "$BASH_COMMAND" >&2
}

# function to display usage information
# $1: ISO_SRC
# $2: WORK_DIR
# $3: TARGET_DRIVE
# $4: MNT_DIR
# $5: CHROOT_DIR
# $6: IMAGE_DIR
usage() {
    ISO_SRC=$1
    WORK_DIR=$2
    TARGET_DRIVE=$3
    MNT_DIR=$4
    CHROOT_DIR=$5
    IMAGE_DIR=$6

    cat <<EOF2
Usage: $0 [--iso-input <path>] [--workdir <path>] [--iso-output <path>] [command]

Default values:
  ISO:          $ISO_SRC
  WORKDIR:      $WORK_DIR
  TARGET_DRIVE: $TARGET_DRIVE
  MNT_DIR:      $MNT_DIR
  CHROOT:       $CHROOT_DIR
  IMAGE:        $IMAGE_DIR
  ISO_OUTPUT:   $ISO_OUTPUT

Commands:
    system_check       check required system commands
    system_prepare     install required system packages

    clean              delete the work directory after confirmation
    prepare            run clean, ensure work directories, and run system_prepare
    extract            mount ISO, copy files, and uncompress linuxfs
    customize          prepare chroot and run commands inside chroot
    shell              open an interactive shell inside the chroot
    make_iso           create final hybrid bootable ISO
    all                run prepare, extract, customize, make_iso
EOF2
}

# System functions
##############################################################################

# System check function to ensure required commands are available
system_check() {
    echo "=== System check ==="

    if ! command -v sudo &> /dev/null; then
        error "sudo not found. Please install it first."
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        error "Please run the script with sudo!"
        exit 1
    fi

    if ! command -v rsync &> /dev/null; then
        error "rsync not found. Please install it first."
        exit 1
    fi

    if ! command -v xorriso &> /dev/null; then
        error "xorriso not found. Please install it first."
        exit 1
    fi

    if ! command -v unsquashfs &> /dev/null; then
        error "unsquashfs not found. Please install squashfs-tools first."
        exit 1
    fi

    success "All required commands are available."
}

# System preparation function to install required packages
system_prepare() {
    echo "=== System preparation ==="
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

# Function for working with work directories
###############################################################################

# function to ensure work directories exist
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
ensure_workdirs() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2
    local IMAGE_DIR=$3
    mkdir -p "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
}

# function to clean up workdir and unmount any mounts
# $1: WORK_DIR
cleanup_workdir() {
    local WORK_DIR=$1
    if [ -d "$WORK_DIR" ]; then
        mountpoints=$(findmnt -rn -o TARGET | awk -v base="$WORK_DIR" '$1 == base || index($1, base "/") == 1' | sort -r)
        if [ -n "$mountpoints" ]; then
            while IFS= read -r mountpoint; do
                sudo umount "$mountpoint" 2>/dev/null || sudo umount -l "$mountpoint" 2>/dev/null || true
            done <<< "$mountpoints"
        fi
    fi
}

# function to ensure work directories exist
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
prepare() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2
    local IMAGE_DIR=$3
    clean "$WORK_DIR"
    echo "=== Prepare, install tools ==="
    ensure_workdirs "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"
    system_prepare
}

# function to customize the chroot environment
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
customize() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2
    local IMAGE_DIR=$3
    echo "=== Customize MX-Chroot ==="
    ensure_workdirs "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"

    if ! chroot_mounts_ready "$CHROOT_DIR"; then
        mount_for_chroot "$CHROOT_DIR" "$WORK_DIR" "$IMAGE_DIR"
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

# function to clean up work directory
# $1: WORK_DIR
clean() {
    local WORK_DIR=$1
    echo "clean $WORK_DIR"
    if [ -d "$WORK_DIR" ]; then
        warning "Work directory $WORK_DIR already exists. It will be deleted."
        read -p "Do you want to continue? (y/n): " choice
        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            echo "Cancelled."
            exit 1
        fi
        cleanup_workdir $WORK_DIR
        sudo rm -rf "$WORK_DIR"
    fi
}

# function to check if chroot mounts are ready
# $1: CHROOT_DIR
chroot_mounts_ready() {
    local CHROOT_DIR=$1
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


# function to mount chroot directories
# $1: CHROOT_DIR
mount_for_chroot() {
    local CHROOT_DIR=$1
    local WORK_DIR=$2
    local IMAGE_DIR=$3
    
    echo "* mounting chroot directories ==="
    
    ensure_workdirs "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"

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

# function to enter an interactive shell inside the chroot
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
shell() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2
    local IMAGE_DIR=$3
    echo "* entering interactive shell inside Chroot ($CHROOT_DIR) ==="
    ensure_workdirs "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"

    if ! chroot_mounts_ready "$CHROOT_DIR"; then
        mount_for_chroot "$CHROOT_DIR" "$WORK_DIR" "$IMAGE_DIR"
    else
        echo "Chroot mounts already exist."
    fi

    sudo chroot "$CHROOT_DIR" /bin/bash
}

# function to unmount chroot mounts
# $1: CHROOT_DIR
unmount_chroot_mounts() {
    local CHROOT_DIR=$1
    for mountpoint in "$CHROOT_DIR/sys" "$CHROOT_DIR/proc" "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev"; do
        if mountpoint -q "$mountpoint"; then
            sudo umount "$mountpoint" 2>/dev/null || sudo umount -l "$mountpoint"
        fi
    done
}

# Linuxfs functions
##############################################################################

# Function to handle linuxfs
# Mount the ISO, copy files, and uncompress linuxfs
# $1: WORK_DIR
# $2: MNT_DIR
# $3: ISO_SRC
# $4: IMAGE_DIR
linuxfs() {
    local WORK_DIR=$1
    local MNT_DIR=$2
    local ISO_SRC=$3
    local IMAGE_DIR=$4

    echo "* mount $ISO_SRC in $MNT_DIR and extract files ==="
    ensure_workdirs "$WORK_DIR" "$CHROOT_DIR" "$IMAGE_DIR"

    mkdir -p "$MNT_DIR"
    sudo mount -o loop "$ISO_SRC" "$MNT_DIR"
    rsync -a --exclude=/antiX/linuxfs "$MNT_DIR/" "$IMAGE_DIR/"
    sudo unsquashfs -d "$CHROOT_DIR" "$MNT_DIR/antiX/linuxfs"
    sudo umount "$MNT_DIR"
}

# Cleanup and squashfs functions
# $1: IMAGE_DIR
# $2: CHROOT_DIR
new_mx_squashfs() {
    local IMAGE_DIR=$1
    local CHROOT_DIR=$2
    echo "* clean up chroot and create new SquashFS ${IMAGE_DIR}/antiX/linuxfs ===" 
    unmount_chroot_mounts $CHROOT_DIR
    mkdir -p "$IMAGE_DIR/antiX"
    sudo rm -f "$IMAGE_DIR/antiX/linuxfs"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Chroot directory does not exist: $CHROOT_DIR"
        exit 1
    fi

    sudo mksquashfs "$CHROOT_DIR" "$IMAGE_DIR/antiX/linuxfs" -comp xz
    (cd "$IMAGE_DIR/antiX" && md5sum linuxfs > linuxfs.md5)
}

# Function to create final hybrid-bootable MX-ISO
# WORK_DIR: $1
# IMAGE_DIR: $2
# ISO_OUTPUT: $3
create_final_iso() {
    local WORK_DIR=$1
    local IMAGE_DIR=$2
    local ISO_OUTPUT=$3
    echo "* create final hybrid-bootable ==="

    if [ ! -d "$IMAGE_DIR/boot" ] || [ ! -f "$IMAGE_DIR/boot/isolinux/isolinux.bin" ]; then
        error "Boot files are missing in $IMAGE_DIR. Run linuxfs/customize/new_mx_squashfs before creating the ISO."
        exit 1
    fi

    local isohdpfx="/usr/lib/ISOLINUX/isohdpfx.bin"
    if [ ! -f "$isohdpfx" ]; then
        isohdpfx="/usr/lib/syslinux/modules/bios/isohdpfx.bin"
    fi

    if [ ! -f "$isohdpfx" ]; then
        error "isohdpfx.bin not found. Install syslinux/isolinux first."
        exit 1
    fi

    xorriso -as mkisofs -r -V "Custom_MX" \
        -o "$ISO_OUTPUT" \
        -J -joliet-long -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat -no-emul-boot \
        -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-mbr "$isohdpfx" \
        -isohybrid-gpt-basdat \
        "$IMAGE_DIR"

    success "DONE! Your MX image is located at: $ISO_OUTPUT ==="
}

##############################################################################
# Script starts here
##############################################################################
main "$@"