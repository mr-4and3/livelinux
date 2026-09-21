#!/bin/bash 

install_rsync() {
    if ! command -v rsync &> /dev/null; then
        echo "rsync is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y rsync
        elif command -v yum &> /dev/null; then
            sudo yum install -y rsync
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y rsync
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y rsync
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm rsync
        else
            echo "No supported package manager found. Please install rsync manually."
            exit 1
        fi
    else
        echo "rsync is already installed."
    fi
}

install_xorriso() {
    if ! command -v xorriso &> /dev/null; then
        echo "xorriso is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y xorriso
        elif command -v yum &> /dev/null; then
            sudo yum install -y xorriso
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y xorriso
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y xorriso
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm xorriso
        else
            echo "No supported package manager found. Please install xorriso manually."
            exit 1
        fi
    else
        echo "xorriso is already installed."
    fi
}

install_unsquashfs() {
    if ! command -v unsquashfs &> /dev/null; then
        echo "unsquashfs is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y squashfs-tools
        elif command -v yum &> /dev/null; then
            sudo yum install -y squashfs-tools
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y squashfs-tools
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y squashfs-tools
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm squashfs-tools
        else
            echo "No supported package manager found. Please install unsquashfs manually."
            exit 1
        fi
    else
        echo "unsquashfs is already installed."
    fi
}

install_veracrypt() {
    if ! command -v veracrypt &> /dev/null; then
        echo "VeraCrypt is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y veracrypt
        elif command -v yum &> /dev/null; then
            sudo yum install -y veracrypt
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y veracrypt
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y veracrypt
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm veracrypt
        else
            echo "No supported package manager found. Please install VeraCrypt manually."
            exit 1
        fi
    else
        echo "VeraCrypt is already installed."
    fi
}

install_lsblk() {
    if ! command -v lsblk &> /dev/null; then
        echo "lsblk is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y util-linux
        elif command -v yum &> /dev/null; then
            sudo yum install -y util-linux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y util-linux
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y util-linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm util-linux
        else
            echo "No supported package manager found. Please install lsblk manually."
            exit 1
        fi
    else
        echo "lsblk is already installed."
    fi
}

install_parted() {
    if ! command -v parted &> /dev/null; then
        echo "parted is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y parted
        elif command -v yum &> /dev/null; then
            sudo yum install -y parted
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y parted
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y parted
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm parted
        else
            echo "No supported package manager found. Please install parted manually."
            exit 1
        fi
    else
        echo "parted is already installed."
    fi
}

install_partprobe() {
    if ! command -v partprobe &> /dev/null; then
        echo "partprobe is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y parted
        elif command -v yum &> /dev/null; then
            sudo yum install -y parted
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y parted
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y parted
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm parted
        else
            echo "No supported package manager found. Please install partprobe manually."
            exit 1
        fi
    else
        echo "partprobe is already installed."
    fi
}

install_dd() {
    if ! command -v dd &> /dev/null; then
        echo "dd is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y coreutils
        elif command -v yum &> /dev/null; then
            sudo yum install -y coreutils
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y coreutils
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y coreutils
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm coreutils
        else
            echo "No supported package manager found. Please install dd manually."
            exit 1
        fi
    else
        echo "dd is already installed."
    fi
}

install_wipefs() {
    if ! command -v wipefs &> /dev/null; then
        echo "wipefs is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y util-linux
        elif command -v yum &> /dev/null; then
            sudo yum install -y util-linux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y util-linux
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y util-linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm util-linux
        else
            echo "No supported package manager found. Please install wipefs manually."
            exit 1
        fi
    else
        echo "wipefs is already installed."
    fi
}

install_blockdev() {
    if ! command -v blockdev &> /dev/null; then
        echo "blockdev is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y util-linux
        elif command -v yum &> /dev/null; then
            sudo yum install -y util-linux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y util-linux
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y util-linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm util-linux
        else
            echo "No supported package manager found. Please install blockdev manually."
            exit 1
        fi
    else
        echo "blockdev is already installed."
    fi
}

install_findmnt() {
    if ! command -v findmnt &> /dev/null; then
        echo "findmnt is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y util-linux
        elif command -v yum &> /dev/null; then
            sudo yum install -y util-linux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y util-linux
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y util-linux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm util-linux
        else
            echo "No supported package manager found. Please install findmnt manually."
            exit 1
        fi
    else
        echo "findmnt is already installed."
    fi
}

install_pv() {
    if ! command -v pv &> /dev/null; then
        echo "pv is not installed. Installing..."
        
        # check for package manager
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y pv
        elif command -v yum &> /dev/null; then
            sudo yum install -y pv
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y pv
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y pv
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm pv
        else
            echo "No supported package manager found. Please install pv manually."
            exit 1
        fi
    else
        echo "pv is already installed."
    fi
}


main() {
    install_rsync
    install_xorriso
    install_unsquashfs
    install_veracrypt
    install_lsblk
    install_parted
    install_partprobe
    install_dd
    install_wipefs
    install_blockdev
    install_findmnt
    install_pv
}

# Call the main function
main