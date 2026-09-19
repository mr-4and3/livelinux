#!/bin/bash
# Script for automatic partitioning and encryption of the USB stick

# Set script to exit immediately if any command fails
set -eE

main() {
    # Main function to execute the script
    # This function is called at the end of the script
    # It handles the command-line arguments and executes the appropriate steps
    # based on the provided options and arguments.
    # It also performs error handling and displays usage information if needed.

    # Trap to ensure cleanup on exit
    trap error_handler ERR

    local LINUX_SIZE_GB=4 # Größe der Linux-Partition in Gigabyte (Rest wird Datenpartition)
    local CRYPTED_PARTITION_SIZE_GB=1 # Größe der verschlüsselten Partition in Gigabyte (0 = Rest des Sticks)
    local NONE_ENCRYPTED_SIZE_GB=1 # Größe der unverschlüsselten Partition in Gigabyte (0 = keine unverschlüsselte Partition)

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --iso)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --iso." >&2
                    exit 1
                fi
                local ISO_PATH="$2"
                shift 2
                ;;
            --usb-drive)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --usb-drive." >&2
                    exit 1
                fi
                local TARGET_DRIVE="$2"
                shift 2
                ;;
            --linux-size)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --linux-size." >&2
                    exit 1
                fi
                local LINUX_SIZE_GB="$2"
                shift 2
                ;;
            --encrypted-size)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --encrypted-size." >&2
                    exit 1
                fi
                local CRYPTED_PARTITION_SIZE_GB="$2"
                shift 2
                ;;
            --none-encrypted-size)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --none-encrypted-size." >&2
                    exit 1
                fi
                local NONE_ENCRYPTED_SIZE_GB="$2"
                shift 2
                ;;
            --sizes)
                if [[ $# -lt 2 ]]; then
                    echo "[!] Missing value for --sizes." >&2
                    exit 1
                fi
                
                IFS=',' read -r LINUX_SIZE_GB CRYPTED_PARTITION_SIZE_GB NONE_ENCRYPTED_SIZE_GB <<< "$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;

                system_check|list_sticks|parted|format|update_linux|encrypt|format_data|all)
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

    if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
        POSITIONAL=(all)
    fi

    validate_size "--linux-size" "$LINUX_SIZE_GB" false
    validate_size "--encrypted-size" "$CRYPTED_PARTITION_SIZE_GB" true

    STEP=${POSITIONAL[0]:-all}

    if [[ "$STEP" != system_check && "$STEP" != list_sticks && "$EUID" -ne 0 ]]; then
        echo "[!] Please run the script with sudo!"
        exit 1
    fi

    # Execute the selected positional argument (step)
    case "$STEP" in 
        system_check)
            system_check
            ;;
        list_sticks)
            list_sticks 
            exit 0
            ;;
        parted)
            parted "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
            exit 0
            ;;
        format)
            format "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
            exit 0
            ;;
        update_linux)
            if [[ -z "${TARGET_DRIVE:-}" || -z "${ISO_PATH:-}" ]]; then
                echo "[!] update_linux requires --usb-drive and --iso." >&2
                usage >&2
                exit 1
            fi
            update_linux_partition "$TARGET_DRIVE" "$ISO_PATH"
            exit 0
            ;;
        encrypt)
            if [[ -z "${TARGET_DRIVE:-}" ]]; then
                echo "[!] encrypted_partition requires --usb-drive" >&2
                usage >&2
                exit 1
            fi
            encrypt "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB"
            exit 0
            ;;
        format_data)
            format_none_encrypted_partition "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
            ;;
        all)
            if [[ -z "${TARGET_DRIVE:-}" ]]; then
                list_sticks
                exit 1
            fi

            all "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$ISO_PATH" "$CRYPTED_PARTITION_SIZE_GB"
            ;;
        *)
            echo "Unknown step: $STEP"
            usage
            exit 1
            ;;
    esac

    echo "'$STEP' completed."
}

# make the complete deployment process available as a single function for easier testing
# $1: Target drive (e.g., /dev/sdb)
# $2: LINUX_SIZE_GB (size of the Linux partition in GB)
# $3: ISO_PATH (path to the custom Linux ISO)
# $4: CRYPTED_PARTITION_SIZE_GB (size of the encrypted partition in GB)

all() {
    local TARGET_DRIVE="$1"
    local LINUX_SIZE_GB="$2"
    local ISO_PATH="$3"
    local CRYPTED_PARTITION_SIZE_GB="$4"

    system_check
    if  ! confirm_target_drive "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" ; then
        echo "[!] Target drive not confirmed. Aborting."
        exit 1
    fi
    
    echo "--------------------------------------------------------"
    echo "Starting deployment to $TARGET_DRIVE"
    echo "Linux Partition Size: ${LINUX_SIZE_GB} GB"
    
    if [ -n "$CRYPTED_PARTITION_SIZE_GB" ] || [ -n "$NONE_ENCRYPTED_SIZE_GB" ]; then
        if (( "$CRYPTED_PARTITION_SIZE_GB" > 0 )); then
            echo "Encrypted Data Partition Size: ${CRYPTED_PARTITION_SIZE_GB} GB"
        else
            echo "No Encrypted Data Partition will be created."
        fi
    fi
    echo "--------------------------------------------------------"


    delete_existing_partition_table "$TARGET_DRIVE" 
    format "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
    update_linux_partition "$TARGET_DRIVE" "$ISO_PATH"
    if (( CRYPTED_PARTITION_SIZE_GB > 0 )); then
        encrypt "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB"
    fi
    if (( NONE_ENCRYPTED_SIZE_GB > 0 )); then
        format_none_encrypted_partition "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
    fi
}

# Function to format the target drive and create partitions
# $1: Target drive (e.g., /dev/sdb)
# $2: LINUX_SIZE_GB (size of the Linux partition in GB)
# $3: CRYPTED_PARTITION_SIZE_GB (size of the encrypted partition in GB)
# $4: NONE_ENCRYPTED_SIZE_GB (size of the unencrypted partition in GB)
format() {
    local TARGET_DRIVE="$1"
    local LINUX_SIZE_GB="$2"
    local CRYPTED_PARTITION_SIZE_GB="$3"
    local NONE_ENCRYPTED_SIZE_GB="$4"

    if [[ -z "${TARGET_DRIVE:-}" ]]; then
        list_sticks
        exit 1
    fi

    confirm_target_drive "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
    delete_existing_partition_table "$TARGET_DRIVE"
    parted "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
    encrypt "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
    format_none_encrypted_partition "$TARGET_DRIVE" "$LINUX_SIZE_GB" "$CRYPTED_PARTITION_SIZE_GB" "$NONE_ENCRYPTED_SIZE_GB"
}

# Function to handle errors and display the command that caused the error
#############################################################################
error_handler() {
    local exit_code=$?
    printf '\033[31mERROR: command failed with exit code %d: %s\033[0m\n' \
        "$exit_code" "$BASH_COMMAND" >&2
}

warning() {
    printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2
}

debug() {
    printf '\033[36mDEBUG: %s\033[0m\n' "$*" >&2
}

error() {
    printf '\033[31mERROR: %s\033[0m\n' "$*" >&2
}
usage() {
    cat <<EOF
Usage: sudo $0 [options] [step]

Deploys a custom Linux ISO to a USB drive.
The selected drive is completely erased.

Options:
    --iso <path>                 Path to the custom Linux ISO
                                                             (default: $ISO_PATH)
    --usb-drive <path>           Existing USB disk for update_linux_partition
    --linux-size <gigabytes>     Size of partition 1 in GB
                                                             (default: $LINUX_SIZE_GB)
  --encrypted-size <gigabytes> Size of the VeraCrypt-encrypted data partition in GB
                               (default: $CRYPTED_PARTITION_SIZE_GB;
                                0 = remaining space)
  -h, --help                   Show this help and exit

Steps (default: all):
  system_check                 Check required commands
  list_sticks                  List disks and ask for a target
  format                       Erase signatures and create a GPT
  update_linux_partition       Replace only partition 1; keep partition 2

The script creates:
  Partition 1                  Custom Linux ISO image
  Partition 2                  VeraCrypt-encrypted exFAT data partition

The deployment step requires a USB-compatible ISO layout. The generated ISO
must be tested on the target hardware before relying on it for booting.

Example:
  sudo $0 --iso /path/to/custom-linux.iso --linux-size 15 --encrypted-size 20
EOF
}

# Function to validate that a given size is a positive integer
#$1: Name of the size parameter (for error messages)
#$2: Value of the size parameter
#$3: Allow zero (true/false) - if true, zero is allowed as a valid value

validate_size() {
    local name="$1"
    local value="$2"
    local allow_zero="$3"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$allow_zero" != true && "$value" == 0 ]]; then
        echo "[!] $name must be an integer greater than zero." >&2
        exit 1
    fi
}

# Check for installed veracrypt
check_veracrypt_installed() {
    if ! command -v veracrypt &> /dev/null; then
        echo "[!] VeraCrypt (CLI) not found. Try to install it first."
        sudo apt-get update
        sudo apt-get install -y veracrypt
        echo "Check if VeraCrypt is installed correctly and rerun the script."
        if ! command -v veracrypt &> /dev/null; then
            echo "[!] VeraCrypt installation failed. Please install it manually."
            exit 1
        fi
    fi
}

system_check() {
    if [ "$EUID" -ne 0 ]; then
        echo "[!] Please run the script with sudo!"
        exit 1
    fi

    check_veracrypt_installed
    # Check for required system commands
    local required_commands=("lsblk" "parted" "partprobe" "dd" "veracrypt" "wipefs" "blockdev" "findmnt" "pv")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "[!] Required command '$cmd' not found. Please install it."
            exit 1
        fi
    done
}

# Function to check if the target drive is the same as the system disk
# $1: Target drive (e.g., /dev/sdb)
check_target_is_not_system_disk() {
    local TARGET_DRIVE="$1"
    local root_source root_disk
    root_source=$(findmnt -no SOURCE /)
    root_disk=$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)

    if [ -n "$root_disk" ] && [ "$TARGET_DRIVE" = "/dev/$root_disk" ]; then
        echo "[!] Refusing to erase the disk containing the running system: $TARGET_DRIVE" >&2
        exit 1
    fi
}

# Function to confirm the target drive with the user
# $1: Target drive (e.g., /dev/sdb)
# $2: LINUX_SIZE_GB (size of the Linux partition in GB)
# $3: CRYPTED_PARTITION_SIZE_GB (size of the encrypted partition in GB)
# $4: NONE_ENCRYPTED_SIZE_GB (size of the unencrypted partition in GB)
confirm_target_drive() {
    local TARGET_DRIVE=$1
    local LINUX_SIZE_GB=$2
    local CRYPTED_PARTITION_SIZE_GB=$3
    local NONE_ENCRYPTED_SIZE_GB=$4

    # Confirm the target drive with the user
    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        list_sticks
    fi

    if [ "$(lsblk -ndo TYPE "$TARGET_DRIVE")" != disk ]; then
        echo "[!] Target must be a whole disk, not a partition or mapped device." >&2
        exit 1
    fi
    check_target_is_not_system_disk

    # Security warning and confirmation
    echo "--------------------------------------------------------"
    echo "WARNING: All data on $TARGET_DRIVE will be completely DELETED!"
    echo "Linux Partition: ${LINUX_SIZE_GB} GB"
    if [ "$CRYPTED_PARTITION_SIZE_GB" ]; then
        if (( CRYPTED_PARTITION_SIZE_GB > 0 )); then
            echo "Encrypted Data Partition: ${CRYPTED_PARTITION_SIZE_GB} GB (VeraCrypt + exFAT)"
        else
            echo "Encrypted Data Partition: no encrypted partition created"
        fi
    else
        echo "Encrypted Data Partition: Remaining space (VeraCrypt + exFAT)"
    fi
    if [ "$NONE_ENCRYPTED_SIZE_GB" ]; then
        if (( NONE_ENCRYPTED_SIZE_GB > 0 )); then
            echo "Unencrypted Data Partition: ${NONE_ENCRYPTED_SIZE_GB} GB"
        fi
    fi
    echo "--------------------------------------------------------"
    read -rp "Are you absolutely sure? (yes/NO): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
    return 
}

# Function to delete existing partition table and wipe filesystem signatures
# $1: Target drive (e.g., /dev/sdb)
delete_existing_partition_table() {
    local TARGET_DRIVE="$1"
    
    # check for root privileges (if not, exit with error)
    check_root

    # Delete existing partition table and wipe filesystem signatures
    ##############################################################################
    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        list_sticks
        exit 1
    fi



    debug "* delete existing partition table and mounts ==="
    # Unmount partitions, in case of automatic mount
    while IFS= read -r partition; do
        sudo umount "$partition" 2>/dev/null || true
    done < <(lsblk -lnpo NAME "$TARGET_DRIVE" | tail -n +2)
    # Delete existing partition table and wipe filesystem signatures
    sudo wipefs -a "$TARGET_DRIVE"
    debug "[*] Existing partition table and filesystem signatures wiped on $TARGET_DRIVE."

    # Create new partition table and partitions
    ##############################################################################
    debug "* create new partition table (GPT) ==="
    command parted -s "$TARGET_DRIVE" mklabel gpt
    debug "[*] New partition table created on $TARGET_DRIVE."
    debug "delete_existing_partition_table completed."
}

# Function to create the data partition for encrypted data on the target drive
# $1: Target drive (e.g., /dev/sdb)
# $2: LINUX_SIZE_GB (size of the Linux partition in GB)
# $3: CRYPTED_PARTITION_SIZE_GB (size of the encrypted partition in GB)
# $4: NONE_ENCRYPTED_SIZE_GB (size of the unencrypted partition in GB)
parted() {
    local TARGET_DRIVE="$1"
    local LINUX_SIZE_GB="$2"
    local CRYPTED_PARTITION_SIZE_GB="$3"
    local NONE_ENCRYPTED_SIZE_GB="$4"

    # check for root privileges (if not, exit with error)
    check_root

    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        list_sticks
        exit 1
    fi

    delete_existing_partition_table "$TARGET_DRIVE"

    debug "* create partitions on $TARGET_DRIVE"
    
    # Create linux partition
    #############################################################################
    debug "** create Linux Partition "
    debug "*** Create partition of type \"Primary\" from 1MB up to wanted size"
    command parted -s "$TARGET_DRIVE" mkpart primary 1MiB "${LINUX_SIZE_GB}GiB"
    debug "** Mark the partition as bootable for UEFI systems"
    command parted -s "$TARGET_DRIVE" set 1 esp on

    # Update the kernel's partition table so the new partition is visible.
    command partprobe "$TARGET_DRIVE"
    sleep 2

    debug "[**] Linux partition created on $TARGET_DRIVE (1-${LINUX_SIZE_GB}GiB)."
 
    # Create encrypted data partition 
    #############################################################################
    if [ "$CRYPTED_PARTITION_SIZE_GB" -gt 0 ] && [ "$NONE_ENCRYPTED_SIZE_GB" -gt 0 ]; then
        debug "** create data partitions for encrypted data and non-encrypted data ==="
        # Create the requested size, or use all remaining space when it does not fit.
        DEVICE_SIZE_BYTES=$(blockdev --getsize64 "$TARGET_DRIVE")
        LINUX_SIZE_BYTES=$((LINUX_SIZE_GB * 1024 * 1024 * 1024))
        CRYPTED_SIZE_BYTES=$((CRYPTED_PARTITION_SIZE_GB * 1024 * 1024 * 1024))
        NONE_ENCRYPTED_SIZE_BYTES=$((NONE_ENCRYPTED_SIZE_GB * 1024 * 1024 * 1024))
        AVAILABLE_SIZE_BYTES=$((DEVICE_SIZE_BYTES - LINUX_SIZE_BYTES))

        if (( CRYPTED_PARTITION_SIZE_GB == 0 || (CRYPTED_SIZE_BYTES + NONE_ENCRYPTED_SIZE_BYTES) > AVAILABLE_SIZE_BYTES )); then
            debug "[**] Requested data partition does not fit; using the remaining space."
            command parted -s "$TARGET_DRIVE" mkpart primary "${LINUX_SIZE_GB}GiB" 100%
        else
            CRYPTED_PARTITION_END_GB=$((LINUX_SIZE_GB + CRYPTED_PARTITION_SIZE_GB))
            NONE_ENCRYPTED_PARTITION_END_GB=$((CRYPTED_PARTITION_END_GB + NONE_ENCRYPTED_SIZE_GB))
            debug "[**] Creating encrypted partition from ${LINUX_SIZE_GB}GiB to ${CRYPTED_PARTITION_END_GB}GiB and unencrypted partition from ${CRYPTED_PARTITION_END_GB}GiB to ${NONE_ENCRYPTED_PARTITION_END_GB}GiB"
            command parted -s "$TARGET_DRIVE" mkpart primary "${LINUX_SIZE_GB}GiB" "${CRYPTED_PARTITION_END_GB}GiB"
            command parted -s "$TARGET_DRIVE" mkpart primary "${CRYPTED_PARTITION_END_GB}GiB" "${NONE_ENCRYPTED_PARTITION_END_GB}GiB"
        fi

        # Update the kernel's partition table
        command partprobe "$TARGET_DRIVE"
        sleep 2

        # Definition of partition paths (e.g., /dev/sdb1 or /dev/nvme0n1p1)
        if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
            PART2="${TARGET_DRIVE}p2"
        else
            PART2="${TARGET_DRIVE}2"
        fi
        debug "[**] Data partition created on $TARGET_DRIVE (Linux: ${LINUX_SIZE_GB}GiB, Data: ${CRYPTED_PARTITION_SIZE_GB}GiB)."
    else
        PART2=""
    fi
    debug "[*] create_partition completed."
}

# Function to update the Linux partition with a new ISO while keeping the second partition intact
# $1: Target drive (e.g., /dev/sdb)
# $2: ISO_PATH (path to the new custom Linux ISO)
# 
update_linux_partition() {
    local TARGET_DRIVE="$1"
    local ISO_PATH="$2"
    local linux_partition iso_size_bytes partition_size_bytes confirmation

    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        error "[!] A valid whole USB disk is required via --target-drive." >&2
        exit 1
    fi

    if [ "$(lsblk -ndo TYPE "$TARGET_DRIVE")" != disk ]; then
        error "[!] Target must be a whole disk, not a partition: $TARGET_DRIVE" >&2
        exit 1
    fi
    check_target_is_not_system_disk "$TARGET_DRIVE"

    if [ ! -f "$ISO_PATH" ]; then
        error "[!] ISO file not found: $ISO_PATH" >&2
        exit 1
    fi

    linux_partition=$(lsblk -nrpo NAME,TYPE "$TARGET_DRIVE" | awk '$2 == "part" { print $1; exit }')
    if [ -z "$linux_partition" ] || [ ! -b "$linux_partition" ]; then
        error "[!] First partition not found on $TARGET_DRIVE." >&2
        exit 1
    fi

    iso_size_bytes=$(stat -c '%s' "$ISO_PATH")
    partition_size_bytes=$(blockdev --getsize64 "$linux_partition")
    if (( iso_size_bytes > partition_size_bytes )); then
        error "[!] ISO does not fit in $linux_partition. $iso_size_bytes > $partition_size_bytes" >&2
        exit 1
    fi

    if ! mountpoint -q "$linux_partition"; then
        debug "[*] $linux_partition is not mounted."
    else
        sudo umount "$linux_partition" || {
            error "[!] Could not unmount $linux_partition before writing the ISO." >&2
            exit 1
        }
    fi

    echo "--------------------------------------------------------"
    echo "WARNING: Only $linux_partition will be overwritten."
    echo "Partition 2 and the partition table will not be changed."
    echo "ISO: $ISO_PATH"
    echo "--------------------------------------------------------"
    read -r -p "Continue? (yes/NO): " confirmation
    if [ "$confirmation" != yes ]; then
        error "Aborted."
        exit 1
    fi

    debug "[*] Writing ISO image to $linux_partition... Please wait."
    pv "$ISO_PATH" | sudo dd of="$linux_partition" bs=8M conv=fsync 
    sudo partprobe "$TARGET_DRIVE" 2>/dev/null || true
    debug "[*] Updated $linux_partition. Partition 2 was not modified."
}

# Function to create an encrypted data partition using VeraCrypt
# $1: Target drive (e.g., /dev/sdb)
# $2: LINUX_SIZE_GB (size of the Linux partition in GB)
encrypt() {
    local TARGET_DRIVE="$1"
    local LINUX_SIZE_GB="$2"

    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        list_sticks
        exit 1
    fi

    # Check existence of the second partition
    if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
        PART2="${TARGET_DRIVE}p2"
    else
        PART2="${TARGET_DRIVE}2"
    fi

    # Check if the second partition exists
    if [ ! -b "$PART2" ]; then
        error "[!] Second partition not found: $PART2" >&2
        exit 1
    fi

    # Check size of the second partition
    local partition_size_bytes
    partition_size_bytes=$(blockdev --getsize64 "$PART2")
    
    # Confirm the encryption of the second partition with the user
    warning "$PART2 will be formatted and encrypted with VeraCrypt. All data on this partition will be lost!"
    read -r -p "Do you want to continue? (yes/NO): " confirmation
    if [ "$confirmation" != yes ]; then
        error "Aborted."
        exit 1
    fi

    # Create encrypted data partition with VeraCrypt
    ##############################################################################
    debug "create Encrypted Data Partition with VeraCrypt "
    debug "--------------------------------------------------------"
    echo "Please set a password for your encrypted volume."
    echo "Windows computers will need this password later to unlock it!"
    echo "--------------------------------------------------------"

    # VeraCrypt command-line command to create the encrypted volume
    # --volume-type=normal: Standard-VeraCrypt container
    # --encryption=AES: Secure and extremely fast standard (hardware-accelerated)
    # --hash=SHA-512: Secure cryptographic hash
    # --filesystem=exfat: Guaranteed native readability under Windows and Linux
    sudo veracrypt --text --create "$PART2" \
        --volume-type=normal \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=exfat \
        --pim=0 \
        --keyfiles=""
    
    debug "[*] Encrypted data partition created on $PART2."

    return 0
}

# Function to format the third partition as exFAT for unencrypted data storage
# $1: Target drive (e.g., /dev/sdb)
format_none_encrypted_partition() {
    local TARGET_DRIVE="$1"
    
    if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
        list_sticks
        exit 1
    fi

    # Check existence of the third partition
    if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
        PART3="${TARGET_DRIVE}p3"
    else
        PART3="${TARGET_DRIVE}3"
    fi

    # Check if the third partition exists
    if [ ! -b "$PART3" ]; then
        error "[!] Third partition not found: $PART3" >&2
        exit 1
    fi

    read -r -p "Do you want to format the third partition $PART3 as exFAT for unencrypted data storage? (yes/NO): " confirmation
    if [ "$confirmation" != yes ]; then
        error "Aborted."
        exit 1
    fi
    # Format the third partition as exFAT for unencrypted data storage
    debug "Formatting unencrypted data partition $PART3 as exFAT..."
    sudo mkfs.exfat -n "DATA" "$PART3"
    debug "[*] Unencrypted data partition formatted on $PART3."
}

# list available drives and prompt user for target USB stick
# $1: NO_WARNING (optional, true/false) - if true, exit without stop the script, if no target drive is specified
list_sticks() {
    # List available drives and prompt user for target USB stick
    debug "* list available usb sticks "
    echo "--------------------------------------------------------"

    STICKS=$(lsblk -S -dnpo NAME,TRAN | awk '$2 == "usb" || $2 == "disk" {print $1}' || true)

    while IFS= read -r NAME; do
        [ -n "$NAME" ] || continue
        SIZE=$(lsblk -dno SIZE "$NAME")
        MODEL=$(lsblk -dno MODEL "$NAME")
        TRAN=$(lsblk -dno TRAN "$NAME")
        echo "Name: $NAME, Size: $SIZE, Model: $MODEL, Transport: $TRAN"
    done <<< "$STICKS"

    echo "--------------------------------------------------------"
}

# Script starts here
##############################################################################
main "$@"