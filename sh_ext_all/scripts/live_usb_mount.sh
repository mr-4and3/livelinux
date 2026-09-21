#!/bin/bash
set -u

LOG_FILE="/var/log/live-usb-mount.log"
MOUNT_ROOT="/mnt"

log() {
    local msg="$*"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$LOG_FILE"
    if command -v logger >/dev/null 2>&1; then
        logger -t live-usb "$msg"
    fi
}

usb_disk() {
    lsblk -dn -o NAME,TYPE,TRAN 2>/dev/null | awk '$2 == "disk" && $3 == "usb" { print "/dev/" $1; exit }'
}

mount_partition() {
    local partition="$1"
    local mountpoint="$2"
    local mount_opts="rw,uid=0,gid=0,umask=0000"

    if [ -z "$partition" ] || [ ! -b "$partition" ]; then
        return 0
    fi

    if mountpoint -q "$mountpoint"; then
        chmod 0777 "$mountpoint"
        log "already mounted: $mountpoint"
        return 0
    fi

    local fstype
    fstype="$(blkid -o value -s TYPE "$partition" 2>/dev/null || true)"

    if [ -n "$fstype" ]; then
        case "$fstype" in
            exfat)
                mount -t exfat -o "$mount_opts" "$partition" "$mountpoint" 2>/dev/null || log "failed to mount $partition as exfat" ;;
            ntfs)
                mount -t ntfs -o "$mount_opts" "$partition" "$mountpoint" 2>/dev/null || log "failed to mount $partition as ntfs" ;;
            vfat)
                mount -t vfat -o "$mount_opts" "$partition" "$mountpoint" 2>/dev/null || log "failed to mount $partition as vfat" ;;
            *)
                mount -o "$mount_opts" "$partition" "$mountpoint" 2>/dev/null || log "failed to mount $partition with default driver" ;;
        esac
    else
        mount -o "$mount_opts" "$partition" "$mountpoint" 2>/dev/null || log "failed to mount $partition without detected fs type"
    fi

    if mountpoint -q "$mountpoint"; then
        chmod 0777 "$mountpoint"
        log "mounted $partition on $mountpoint"
    else
        log "partition $partition is not mounted on $mountpoint"
    fi
}

main() {
    mkdir -p "$MOUNT_ROOT" "$MOUNT_ROOT/usb2" "$MOUNT_ROOT/usb3"
    chmod 0777 "$MOUNT_ROOT" "$MOUNT_ROOT/usb2" "$MOUNT_ROOT/usb3"

    local disk
    disk="$(usb_disk)"

    if [ -z "$disk" ]; then
        log "no USB disk found"
        exit 0
    fi

    log "USB disk detected: $disk"

    local part2="${disk}2"
    local part3="${disk}3"
    if [ ! -b "$part2" ] && [ -b "${disk}p2" ]; then
        part2="${disk}p2"
    fi
    if [ ! -b "$part3" ] && [ -b "${disk}p3" ]; then
        part3="${disk}p3"
    fi

    mount_partition "$part2" "$MOUNT_ROOT/usb2"
    mount_partition "$part3" "$MOUNT_ROOT/usb3"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
