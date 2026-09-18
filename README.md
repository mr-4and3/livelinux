# Custom antiX / MX Live ISO Builder

This project builds a customized, hybrid-bootable antiX or MX Linux ISO from a source ISO, modifies the extracted live system in a chroot, and then rebuilds the live filesystem and bootable image.

The project focuses on the active build workflow used for live ISO customization and USB deployment. Older helper scripts kept in an archive directory are not part of the main documentation.

## What this project does

- extracts a source ISO into a working directory
- mounts the live filesystem and unpacks its `antiX/linuxfs`
- customizes the system inside a chroot
- rebuilds the SquashFS live system
- creates a final bootable ISO
- writes the ISO to a USB stick with a second encrypted data partition

## Main scripts

- `iso-change.sh` — main ISO creation workflow
- `deploy-to-usb.sh` — deploys the generated ISO to USB and creates the encrypted data partition

Archive or legacy helper scripts are intentionally not documented here because they are not part of the current active workflow.

## Requirements

- Debian-based Linux host, preferably MX Linux or Ubuntu
- root privileges via `sudo`
- valid antiX or MX Linux ISO
- internet access when packages are installed inside the chroot
- enough disk space for the extracted live system and rebuilt image
- USB drive large enough for the Linux + data partitions

Required host tools:

- `bash`
- `sudo`
- `mount` / `umount`
- `rsync`
- `unsquashfs` / `mksquashfs`
- `xorriso`
- `chroot`
- `findmnt`
- `realpath`
- `md5sum`
- `lsblk`
- `parted`
- `partprobe`
- `dd`

The script installs the packages needed for the ISO build step, especially `squashfs-tools`, `xorriso`, and `rsync`.

## Quick start

Show help:

```bash
sudo ./iso-change.sh --help
```

Build a custom ISO from a source image:

```bash
sudo ./iso-change.sh \
  --iso-input /path/to/source.iso \
  --workdir ./work \
  --iso-output ./custom-linux.iso \
  all
```

Create the final ISO file in the working directory:

```bash
sudo ./iso-change.sh \
  --workdir ./work \
  --iso-output ./custom-linux.iso \
  make_iso
```

Deploy the ISO to a USB drive:

```bash
sudo ./deploy-to-usb.sh
```

## Build workflow

The standard build sequence is:

```text
prepare
linuxfs
customize
new_mx_squashfs
create_final_iso
```

The final ISO is created as:

```text
./custom-linux.iso
```

## Working directories

The script uses these folders under the working directory:

- `work/mnt` — mounted source ISO
- `work/chroot` — extracted live root filesystem for modifications
- `work/image` — rebuilt ISO content before packaging

## USB layout

The USB deployment script creates a hybrid USB with two main partitions:

1. Partition 1: bootable Linux ISO image
2. Partition 2: VeraCrypt-encrypted exFAT data partition

## Important warning

The USB deployment script completely erases the selected target drive, including its partition table and existing data. Select the correct device carefully and never target the system disk.

## Notes

This repository is designed for rebuilding and customizing a live antiX/MX Linux environment. It is not a general-purpose package manager project and it is not meant to document every archived helper script from older experiments.
