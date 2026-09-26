#!/bin/bash

set_keyboard_de() {
    local CHROOT_DIR="$1"
    if [ ! -d "$CHROOT_DIR" ]; then
        echo "Error: Chroot directory '$CHROOT_DIR' does not exist."
        return 1
    fi

    sudo mkdir -p "$CHROOT_DIR/etc/X11/xorg.conf.d"

    sudo tee "$CHROOT_DIR/etc/default/keyboard" >/dev/null <<'EOF'
XKBLAYOUT="de"
XKBMODEL="pc105"
XKBVARIANT="nodeadkeys"
XKBOPTIONS=""
BACKSPACE="guess"
EOF

    sudo tee "$CHROOT_DIR/etc/vconsole.conf" >/dev/null <<'EOF2'
KEYMAP=de
FONT=lat9w-16
EOF2

    sudo tee "$CHROOT_DIR/etc/X11/xorg.conf.d/00-keyboard.conf" >/dev/null <<'EOF3'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "de"
    Option "XkbModel" "pc105"
    Option "XkbVariant" "nodeadkeys"
EndSection
EOF3

    sudo chroot "$CHROOT_DIR" /bin/bash -e <<'EOF4'
export DEBIAN_FRONTEND=noninteractive

if command -v dpkg-reconfigure >/dev/null 2>&1; then
    dpkg-reconfigure -f noninteractive keyboard-configuration >/dev/null 2>&1 || true
fi

if command -v localectl >/dev/null 2>&1; then
    localectl set-x11-keymap de pc105 nodeadkeys >/dev/null 2>&1 || true
fi

if command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap de pc105 nodeadkeys >/dev/null 2>&1 || true
fi
EOF4
}