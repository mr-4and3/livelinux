#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_MOUNT_SCRIPT="$SCRIPT_DIR/live_usb_mount.sh"
KEYBOARD_SCRIPT="$SCRIPT_DIR/set_keyboard.sh"
# source the reusable USB mount logic so it can be reused during customization
if [ -f "$USB_MOUNT_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$USB_MOUNT_SCRIPT"
else
    echo "Missing USB mount script: $USB_MOUNT_SCRIPT" >&2
    exit 1
fi

# source the keyboard setting script
if [ -f "$KEYBOARD_SCRIPT" ]; then
    # shellcheck disable=SC1090
    source "$KEYBOARD_SCRIPT"
else
    echo "Missing keyboard setting script: $KEYBOARD_SCRIPT" >&2
    exit 1
fi


# function to customize the chroot environment
# $1: WORK_DIR
# $2: CHROOT_DIR
# $3: IMAGE_DIR
customize_exe() {
    local WORK_DIR=$1
    local CHROOT_DIR=$2

    if [ ! -f "$USB_MOUNT_SCRIPT" ]; then
        echo "Missing USB mount script: $USB_MOUNT_SCRIPT" >&2
        return 1
    fi

    sudo install -m 0755 "$USB_MOUNT_SCRIPT" "$CHROOT_DIR/usr/local/sbin/live_usb_mount.sh"

    set_keyboard_de "$CHROOT_DIR"

    sudo chroot "$CHROOT_DIR" /bin/bash -e <<'EOF2'
       export DEBIAN_FRONTEND=noninteractive
       apt update
       apt upgrade -y
       apt-get install -y exfat-fuse exfatprogs ntfs-3g dmsetup xdotool tcplay
       apt-get install -y torbrowser-launcher
       apt-get clean
       rm -rf /var/lib/apt/lists/*

       mkdir -p /mnt/usb2 /mnt/usb3 /var/log

       if command -v systemctl >/dev/null 2>&1; then
           cat > /etc/systemd/system/live-usb-mount.service <<'EOF3'
[Unit]
Description=Mount USB partitions for live system
DefaultDependencies=no
After=local-fs.target
Wants=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/live_usb_mount.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF3
           systemctl enable live-usb-mount.service >/dev/null 2>&1 || true
       elif [ -d /etc/init.d ]; then
           cat > /etc/init.d/live-usb-mount <<'EOF4'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          live-usb-mount
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Mount live USB partitions
### END INIT INFO

/usr/local/sbin/live_usb_mount.sh
EOF4
           chmod 0755 /etc/init.d/live-usb-mount
           update-rc.d live-usb-mount defaults >/dev/null 2>&1 || true
       elif [ -f /etc/rc.local ]; then
           if ! grep -Fq '/usr/local/sbin/live_usb_mount.sh' /etc/rc.local; then
               printf '\n/usr/local/sbin/live_usb_mount.sh\n' >> /etc/rc.local
           fi
       else
           printf '#!/bin/bash\n/usr/local/sbin/live_usb_mount.sh\n' > /etc/rc.local
           chmod 0755 /etc/rc.local
       fi
EOF2
}
