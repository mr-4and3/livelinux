#!/bin/bash


set_usb_live_mount() {
    local CHROOT_DIR="$1"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    source "$SCRIPT_DIR/../common.sh"

    if [ ! -d "$CHROOT_DIR" ]; then
        error "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    # Usb mount script
    ###########################################################################
    if [ ! -f "$SCRIPT_DIR/../sh_ext_all/scripts/live_usb_mount.sh" ]; then
        error "Missing USB mount script: $SCRIPT_DIR/../sh_ext_all/scripts/live_usb_mount.sh"
        return 1
    fi

    sudo install -m 0755 "$SCRIPT_DIR/../sh_ext_all/scripts/live_usb_mount.sh" "$CHROOT_DIR/usr/local/sbin/live_usb_mount.sh"

    # Usb mount systemd service
    ###########################################################################
    if [ ! -f "$SCRIPT_DIR/config/live_usb_mount.service" ]; then
        error "Missing USB mount service file: $SCRIPT_DIR/config/live_usb_mount.service"
        return 1
    fi
    sudo install -m 0644 "$SCRIPT_DIR/config/live_usb_mount.service" "$CHROOT_DIR/etc/systemd/system/live_usb_mount.service"

    # Usb mount init script
    ###########################################################################
    if [ ! -f "$SCRIPT_DIR/config/live_usb_mount.init" ]; then
        error "Missing USB mount init script: $SCRIPT_DIR/config/live_usb_mount.init"
        return 1
    fi
    sudo install -m 0755 "$SCRIPT_DIR/config/live_usb_mount.init" "$CHROOT_DIR/etc/init.d/live_usb_mount"

    # set the usb mount script in the chroot environment
    sudo chroot "$CHROOT_DIR" /bin/bash -e <<'EOF'
           export DEBIAN_FRONTEND=noninteractive
       mkdir -p /mnt/usb2 /mnt/usb3 /var/log

       if command -v systemctl >/dev/null 2>&1; then
           systemctl enable live-usb-mount.service >/dev/null 2>&1 || true
       elif [ -d /etc/init.d ]; then
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
EOF
}