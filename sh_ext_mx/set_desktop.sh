#!/bin/bash

# This script sets up the decrypt script in the chroot environment and creates a desktop entry for it.
# $1 CHROOT_DIR: The directory of the chroot environment where the decrypt script will be set up.
# $2 DESKTOP_FILE_NAME: The name of the desktop file to create.
# $3 APP_NAME: The name of the application.
# $4 COMMENT: A comment for the desktop entry.
# $5 EXEC_PATH: The path to the executable.
# $6 ICON_PATH: The path to the icon file.
set_desktop() {
    local CHROOT_DIR="$1"
    local DESKTOP_FILE_NAME="$2"
    local APP_NAME="$3"
    local COMMENT="$4"
    local EXEC_PATH="$5"
    local ICON_PATH="$6"
    local DESKTOP_ENTRY_DIR="$CHROOT_DIR/etc/skel/Desktop/"
    local DESKTOP_ENTRY="$DESKTOP_ENTRY_DIR/$DESKTOP_FILE_NAME"
    
    mkdir -p "$DESKTOP_ENTRY_DIR"
    
    # Create a desktop entry for the custom application
    cat <<EOL > "$DESKTOP_ENTRY"
[Desktop Entry]
Name=$APP_NAME
Comment=$COMMENT
Exec=$EXEC_PATH
Icon=${ICON_PATH}
Terminal=false
Type=Application
Categories=Utility;
EOL

    chmod +x "$DESKTOP_ENTRY"
    echo "Desktop entry for $APP_NAME created at $DESKTOP_ENTRY"
}