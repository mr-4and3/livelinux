#!/bin/bash
# Skript zur automatischen Partitionierung und Verschlüsselung des USB-Sticks
set -e

# === CONFIGURATION ===
ISO_PATH="$HOME/mx-work/custom-mx-linux.iso"
TARGET_DRIVE="" # WIRD UNTEN ABGEFRAGT (z.B. /dev/sdb)
LINUX_SIZE_GB=15 # Größe der Linux-Partition in Gigabyte (Rest wird Datenpartition)

# Sicherheitsabfrage für Root-Rechte
if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run the script with sudo!"
  exit 1
fi

# Überprüfen, ob VeraCrypt installiert ist
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

echo "=== Verfügbare Laufwerke ==="
lsblk -d -n -o NAME,SIZE,MODEL | grep -E "sd|nvme"
echo "------------------------------------------------"
read -p "Bitte den Ziel-USB-Stick eingeben (z.B. /dev/sdb): " TARGET_DRIVE

# Absicherung gegen versehentliches Überschreiben
if [ -z "$TARGET_DRIVE" ] || [ ! -b "$TARGET_DRIVE" ]; then
    echo "[!] Ungültiges Laufwerk angegeben."
    exit 1
fi

echo "========================================================"
echo "ACHTUNG: Alle Daten auf $TARGET_DRIVE werden komplett GELÖSCHT!"
echo "Linux-Partition: ${LINUX_SIZE_GB} GB"
echo "Daten-Partition: Restlicher Speicherplatz (VeraCrypt + exFAT)"
echo "========================================================"
read -p "Bist du absolut sicher? (ja/NEIN): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    echo "Abgebrochen."
    exit 1
fi

echo "=== 1. Vorhandene Partitionstabelle und Mounts löschen ==="
# Partitionen aushängen, falls das System sie automatisch gemountet hat
sudo umount ${TARGET_DRIVE}* 2>/dev/null || true
# Löscht die alten Partitions-Header
sudo wipefs -a "$TARGET_DRIVE"

echo "=== 2. Neue Partitionstabelle erstellen (GPT) ==="
sudo parted -s "$TARGET_DRIVE" mklabel gpt

echo "=== 3. Partition 1 für Linux erstellen ==="
# Erstellt eine Partition vom Typ "Primary" von 1MB bis zur Wunschgröße
sudo parted -s "$TARGET_DRIVE" mkpart primary 1MiB ${LINUX_SIZE_GB}GiB
# Markiert die Partition als bootfähig für UEFI-Systeme
sudo parted -s "$TARGET_DRIVE" set 1 esp on

echo "=== 4. Partition 2 für verschlüsselte Daten erstellen ==="
# Belegt den gesamten restlichen Speicherplatz des Sticks
sudo parted -s "$TARGET_DRIVE" mkpart primary ${LINUX_SIZE_GB}GiB 100%

# Aktualisiere die Kernel-Partitionstabelle
sudo partprobe "$TARGET_DRIVE"
sleep 2

# Definition der Partitions-Pfade (z.B. /dev/sdb1 oder /dev/nvme0n1p1)
if [[ "$TARGET_DRIVE" == *"nvme"* ]]; then
    PART1="${TARGET_DRIVE}p1"
    PART2="${TARGET_DRIVE}p2"
else
    PART1="${TARGET_DRIVE}1"
    PART2="${TARGET_DRIVE}2"
fi

echo "=== 5. MX-Linux ISO auf Partition 1 flashen ==="
# dd schreibt das Image direkt bitgenau auf die erste Partition
echo "[*] Schreibe ISO-Image auf $PART1... Bitte warten."
sudo dd if="$ISO_PATH" of="$PART1" bs=4M status=progress conv=fsync

echo "=== 6. Partition 2 mit VeraCrypt verschlüsseln (exFAT) ==="
echo "--------------------------------------------------------"
echo "Bitte vergib jetzt das Passwort für deinen Datentresor."
echo "Windows-Rechner benötigen dieses Passwort später zum Entsperren!"
echo "--------------------------------------------------------"

# VeraCrypt Kommandozeilen-Befehl zum Erstellen des verschlüsselten Volumes
# --volume-type=normal: Standard-VeraCrypt-Container
# --encryption=AES: Sicherer und extrem schneller Standard (Hardware-beschleunigt)
# --hash=SHA-512: Sicherer kryptografischer Hash
# --filesystem=exfat: Garantiert native Lesbarkeit unter Windows und Linux
sudo veracrypt --text --create "$PART2" \
    --volume-type=normal \
    --encryption=AES \
    --hash=SHA-512 \
    --filesystem=exfat \
    --pim=0 \
    --keyfiles=""

echo "========================================================"
echo "   ERFOLG! Dein sicherer USB-Stick ist einsatzbereit."
echo "========================================================"
echo "Partition 1: Bootfähiges Custom MX-Linux"
echo "Partition 2: Passwortgeschützter Datentresor (exFAT)"
