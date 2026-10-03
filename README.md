# Custom antiX / MX Live ISO Builder

This repository creates a customized live antiX or MX Linux ISO from a source image, modifies the extracted live system in a chroot, rebuilds the SquashFS payload, and packages the result as a bootable ISO. A second script can write that ISO to a USB drive and prepare encrypted and/or unencrypted data partitions.

The active workflow is centered on the scripts in the repository root:

- `install.sh` — installs host dependencies
- `iso-change.sh` — builds and customizes the ISO
- `deploy-to-usb.sh` — deploys the ISO to a USB stick


## What the project does

- validates the system environment
- prepares a working directory
- mounts the source ISO and extracts the live filesystem
- customizes the chrooted live system
- repacks the live filesystem into a new SquashFS image
- creates the final hybrid bootable ISO
- writes the ISO to USB with optional encrypted data storage

## Requirements

- Debian-based Linux host, preferably MX Linux or Ubuntu
- root privileges via `sudo`
- a valid antiX or MX Linux ISO source
- internet access when packages are installed inside the chroot
- enough disk space for the extracted live filesystem and rebuilt image
- a USB drive large enough for the Linux + data partitions

Required host tools include:

- `bash`
- `sudo`
- `rsync`
- `xorriso`
- `unsquashfs`
- `parted`
- `lsblk`
- `findmnt`
- `dd`
- `partprobe`
- `realpath`
- `mount` / `umount`

The helper script `install.sh` installs the common build dependencies automatically, including `rsync`, `xorriso`, `squashfs-tools`, `tcplay`, and partitioning tools.

## Quick start

1. Install the required host packages:

```bash
sudo ./install.sh
```

2. Show the available ISO builder commands:

```bash
sudo ./iso-change.sh --help
```

3. Build a custom ISO from a source image:

```bash
sudo ./iso-change.sh \
  --iso /path/to/source.iso \
  --workdir ./work \
  --iso-output ./custom-linux.iso \
  all
```

4. Deploy the generated ISO to a USB stick:

```bash
sudo ./deploy-to-usb.sh \
  --usb-drive /dev/sdX \
  --iso ./custom-linux.iso \
  --sizes 4,1,1 \
  all
```

The `--sizes` option accepts the format:

```bash
--sizes linux_size,encrypted_size,none_encrypted_size
```

You can also configure each partition size individually:

```bash
sudo ./deploy-to-usb.sh \
  --usb-drive /dev/sdX \
  --iso ./custom-linux.iso \
  --linux-size 4 \
  --encrypted-size 1 \
  --none-encrypted-size 1 \
  all
```

## ISO build workflow

The active sequence in `iso-change.sh` is:

```text
clean
prepare
extract
customize
make-iso
```

The full workflow can also be run as a single command:

```bash
sudo ./iso-change.sh all
```

The script supports these commands:

- `system-check`
- `clean`
- `prepare`
- `extract`
- `customize`
- `shell`
- `make-iso`
- `all`

## Working directories

The build uses the following folders under the selected work directory:

- `work/mnt` — mounted source ISO
- `work/chroot` — extracted live root filesystem for modification
- `work/image` — rebuilt ISO content before packaging

## USB layout

The USB deployment script creates a hybrid USB disk with up to three main partitions:

1. Partition 1: bootable Linux ISO image
2. Partition 2: VeraCrypt-encrypted exFAT data partition
3. Partition 3: optional unencrypted exFAT data partition

Example:

```bash
sudo ./deploy-to-usb.sh --usb-drive /dev/sdX --iso ./custom-linux.iso --sizes 15,20,5 all
```

This creates a live USB with:

- 15 GB Linux partition
- 20 GB encrypted data partition
- 5 GB unencrypted data partition

## Important warnings

- The USB tool permanently deletes the selected target disk and recreates its partition table.
- The script refuses to target the disk containing the running system.
- Double-check the device path before running any destructive command.
- Always test the final ISO on the target hardware before relying on it for production use.

## Notes

This repository is meant for building and customizing a live antiX/MX Linux environment. It is not a general-purpose package manager or a documentation project for every old helper script in the `archive/` folder.
