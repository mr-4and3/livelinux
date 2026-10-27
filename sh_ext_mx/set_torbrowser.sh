#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/set_desktop.sh"

set_torbrowser_LOG_FILE="./set_torbrowser.log"

set_torbrowser_log() {
    local message="$1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$set_torbrowser_LOG_FILE" >&2
}

# This script sets up the Tor Browser in the chroot environment.
set_torbrowser() {
    local CHROOT_DIR=$1
    local DOWNLOAD_DIR=${2:-"./download/torbrowser"}
    local TAR_FILE

    TAR_FILE=$(set_torbrowser_download "" "$DOWNLOAD_DIR") || return 1

    # Unpack the Tor Browser tarball in the chroot environment
    # In deinem Skript (wenn du bereits root bist oder im Chroot arbeitest):
    set_torbrowser_log "Unpacking Tor Browser with tar file: $TAR_FILE"
    set_torbrowser_unpack "$TAR_FILE" "/opt/" "$CHROOT_DIR"
    set_torbrowser_link "$CHROOT_DIR"
    set_torbrowser_desktop "$CHROOT_DIR"
}

set_torbrowser_desktop() {
    set_desktop "$1" \
    "tor-browser.desktop" \
    "Tor Browser" \
    "Tor Browser" \
    "/usr/bin/tor-browser" \
    "tor-browser"
}

set_torbrowser_link() {
    local CHROOT_DIR=$1
    local TOR_BROWSER_DIR="$CHROOT_DIR/opt/tor-browser"
    local TOR_BROWSER_STARTER="/opt/tor-browser/Browser/start-tor-browser"
    local LINK_PATH="/usr/bin/tor-browser"

    if [ ! -d "$TOR_BROWSER_DIR" ]; then
        set_torbrowser_log "Error: Tor Browser directory '$TOR_BROWSER_DIR' does not exist."
        return 1
    fi

    sudo chroot "$CHROOT_DIR" /bin/bash -e -c \
        'ln -sf "$1" "$2"' _ "$TOR_BROWSER_STARTER" "$LINK_PATH"
}

set_torbrowser_unpack() {
    local TAR_FILE=$1
    local DEST_DIR_TARGET=$2
    local CHROOT_DIR=$3
    local DEST_DIR="$CHROOT_DIR/$DEST_DIR_TARGET"
    local TOR_STARTER_SCRIPT="$DEST_DIR/tor-browser/Browser/start-tor-browser"
    if [ ! -f "$TAR_FILE" ]; then
        set_torbrowser_log "Error: Tar file '$TAR_FILE' does not exist."
        return 1
    fi

    mkdir -p "$DEST_DIR" || return 1
    tar -xf "$TAR_FILE" -C "$DEST_DIR" || return 1
    chmod -R 777 "$DEST_DIR" || return 1
    chmod +x "$TOR_STARTER_SCRIPT" || return 1

    # Set the demo user in chroot set enviorment before
    sudo  chroot "$CHROOT_DIR" /bin/bash -e -c \
    'chown -R demo:demo "$1"' _ "$DEST_DIR_TARGET"
}

set_torbrowser_download() {
    local TOR_BROWSER_URL=${1:-"https://aus1.torproject.org/torbrowser/update_3/release/downloads.json"}
    local DOWNLOAD_DIR=${2:-"./download/torbrowser"}
    local DOWNLOADS_JSON
    local DOWNLOAD_URL
    local TAR_FILE

    mkdir -p "$DOWNLOAD_DIR" || return 1

    DOWNLOADS_JSON=$(curl -fsSL "$TOR_BROWSER_URL")
    if [ -z "$DOWNLOADS_JSON" ]; then
        set_torbrowser_log "Error: Failed to fetch download information from $TOR_BROWSER_URL"
        return 1
    fi

    DOWNLOAD_URL=$(printf '%s' "$DOWNLOADS_JSON" | jq -er '.downloads."linux-x86_64".ALL.binary') || return 1
    if [ -z "$DOWNLOAD_URL" ]; then
        set_torbrowser_log "Error: Failed to extract download URL from JSON."
        return 1
    fi

    local SIG_URL
    SIG_URL=$(printf '%s' "$DOWNLOADS_JSON" | jq -er '.downloads."linux-x86_64".ALL.sig') || return 1
    if [ -z "$SIG_URL" ] || [ "$SIG_URL" == "null" ]; then
        set_torbrowser_log "Error: Failed to extract signature URL from JSON."
        return 1
    fi

    local TAR_FILENAME
    TAR_FILENAME=$(basename "$DOWNLOAD_URL")
    local TAR_FILE="$DOWNLOAD_DIR/$TAR_FILENAME"
    local SIG_FILE
    SIG_FILE="$DOWNLOAD_DIR/$(basename "$SIG_URL")"

    # check if the tarball from DOWNLOAD_URL already exists in the download directory
    set_torbrowser_log "Downloading Tor Browser from $DOWNLOAD_URL to $DOWNLOAD_DIR/$TAR_FILENAME"
    # check if the file already exists in the download directory
    if [ -f "$TAR_FILE" ] && [ -f "$SIG_FILE" ]; then
        if ! set_torbrowser_verify_signature "$TAR_FILE" "$SIG_FILE"; then
            set_torbrowser_log "Existing archive/signature pair is invalid. Redownloading..."
            rm -f "$TAR_FILE" "$SIG_FILE" || return 1
        else
            printf '%s\n' "$TAR_FILE"
            return 0
        fi
    fi

    curl -fL -o "$TAR_FILE" "$DOWNLOAD_URL" || return 1
    curl -fL -o "$SIG_FILE" "$SIG_URL" || return 1

    if ! set_torbrowser_verify_signature "$TAR_FILE" "$SIG_FILE"; then
        set_torbrowser_log "Downloaded Tor Browser archive failed signature verification."
        rm -f "$TAR_FILE" "$SIG_FILE" || return 1
        return 1
    fi

    realpath "$TAR_FILE"
}

set_torbrowser_clean() {
    local DOWNLOAD_DIR=${1:-"./download/torbrowser"}
    rm -rf "$DOWNLOAD_DIR"
}

set_torbrowser_verify_signature() {
    local FILE=$1
    local SIG_FILE=$2
    local GNUPG_HOME
    local KEYRING
    local status

    if [ ! -f "$FILE" ]; then
        set_torbrowser_log "Error: File '$FILE' does not exist."
        return 1
    fi

    if [ ! -f "$SIG_FILE" ]; then
        set_torbrowser_log "Error: Signature file '$SIG_FILE' does not exist."
        return 1
    fi

    if ! command -v gpg >/dev/null 2>&1 || ! command -v gpgv >/dev/null 2>&1; then
        set_torbrowser_log "Error: gpg and gpgv are required to verify the Tor Browser signature."
        return 1
    fi

    GNUPG_HOME=$(mktemp -d) || return 1
    chmod 700 "$GNUPG_HOME" || {
        rm -rf "$GNUPG_HOME"
        return 1
    }

    if ! gpg --homedir "$GNUPG_HOME" --batch --auto-key-locate nodefault,wkd \
        --locate-keys torbrowser@torproject.org >>"$set_torbrowser_LOG_FILE" 2>&1; then
        set_torbrowser_log "Error: Could not fetch the Tor Browser signing key via WKD."
        rm -rf "$GNUPG_HOME"
        return 1
    fi

    if ! gpg --homedir "$GNUPG_HOME" --batch --with-colons --fingerprint \
        torbrowser@torproject.org | awk -F: '$1 == "fpr" { print $10 }' |
        grep -Fxq "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"; then
        set_torbrowser_log "Error: Tor Browser signing key fingerprint did not match the trusted key."
        rm -rf "$GNUPG_HOME"
        return 1
    fi

    KEYRING="$GNUPG_HOME/torbrowser.gpg"
    if ! gpg --homedir "$GNUPG_HOME" --batch --export \
        EF6E286DDA85EA2A4BA7DE684E2C6E8793298290 > "$KEYRING"; then
        set_torbrowser_log "Error: Could not export the verified Tor Browser signing key."
        rm -rf "$GNUPG_HOME"
        return 1
    fi

    gpgv --keyring "$KEYRING" "$SIG_FILE" "$FILE" 2>&1 |
        tee -a "$set_torbrowser_LOG_FILE" >&2
    status=${PIPESTATUS[0]}
    rm -rf "$GNUPG_HOME"
    if [ "$status" -ne 0 ]; then
        set_torbrowser_log "Error: OpenPGP signature verification failed for '$FILE'."
        return 1
    fi

    set_torbrowser_log "OpenPGP signature verified for '$FILE'."
    return 0
}

# Run the function if the script is executed directly
if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
    if [ $# -ne 1 ]; then
        echo "Usage: $0 <chroot_directory>"
        exit 1
    fi

    CHROOT_DIR=$1
    set_torbrowser "$CHROOT_DIR"
    #set_torbrowser_download "" "./download/torbrowser"
fi
