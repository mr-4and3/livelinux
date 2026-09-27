#!/bin/bash


set_torbrowser() {
    CHROOT_DIR=$1
    DOWNLOAD_DIR="./download/torbrowser"

    
    # 1. Benötigte Verzeichnisse erstellen
    rm -rf $DOWNLOAD_DIR/
    mkdir -p $DOWNLOAD_DIR/

    curl -LO --output-dir $DOWNLOAD_DIR/ $(curl -s https://aus1.torproject.org/torbrowser/update_3/release/downloads.json | jq -r '.downloads."linux-x86_64".ALL.binary')

    TAR_FILE=$(realpath "$DOWNLOAD_DIR"/tor-browser-linux-x86_64-*.tar.xz)

    # Unpack the Tor Browser tarball in the chroot environment
    # In deinem Skript (wenn du bereits root bist oder im Chroot arbeitest):
    tar -xf "$TAR_FILE" -C "$CHROOT_DIR/opt/"
    chmod -R 777 "$CHROOT_DIR/opt/tor-browser"

    cat <<'EOF' > "$CHROOT_DIR/usr/bin/tor-browser"
#!/bin/bash
# Set the environment variable for the Tor Browser directory
exec /opt/tor-browser/start-tor-browser "$@"
EOF

    chmod +x "$CHROOT_DIR/usr/bin/tor-browser"
    
    # Create a desktop entry for the Tor Browser
    DESKTOP_ENTRY="$CHROOT_DIR/usr/share/applications/tor-browser.desktop"
    cat <<EOL > "$DESKTOP_ENTRY" 
[Desktop Entry]
Name=Tor Browser
Comment=Tor Browser
Exec=/usr/bin/tor-browser
Icon=tor-browser
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOL

}

# Run the function if the script is executed directly
if [ "$0" = "$BASH_SOURCE" ]; then
    if [ $# -ne 1 ]; then
        echo "Usage: $0 <chroot_directory>"
        exit 1
    fi

    CHROOT_DIR=$1
    set_torbrowser "$CHROOT_DIR"
fi