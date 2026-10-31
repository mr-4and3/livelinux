# Custom antiX / MX Live ISO Builder

This repository creates a customized live antiX or MX Linux ISO from a source image, modifies the extracted live system in a chroot, rebuilds the SquashFS payload, and packages the result as a bootable ISO. A second script can write that ISO to a USB drive and prepare encrypted and/or unencrypted data partitions.

The active workflow scripts and their helper scripts are in `scrips/`:

- `install.sh` — installs host dependencies (repository root)
- `scrips/st-iso.sh` — builds and customizes the ISO
- `scrips/st-usb.sh` — deploys the ISO to a USB stick
- `scrips/st-qemu-chroot.sh` — boots the extracted chroot directly in QEMU
- `scrips/sh_ext_mx/` and `scrips/sh_ext_all/` — scripts and assets used to customize the live system

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

## Development checks

When developing the shell scripts, run `setup-pre-commit.sh` once after cloning the repository:

```bash
./setup-pre-commit.sh
```

The setup script installs `pre-commit` if needed, enables the local Git hook, and checks all existing files. Shell scripts are then checked with ShellCheck before each commit. Git does not enable repository hooks automatically on clone, so this setup step is needed for local checks. GitHub Actions also runs the same pre-commit checks on pushes and pull requests.

## Quick start

1. Install the required host packages:

```bash
sudo ./install.sh
```

2. Show the available ISO builder commands:

```bash
sudo ./scrips/st-iso.sh --help
```

3. Build a custom ISO from a source image:

```bash
sudo ./scrips/st-iso.sh \
  --iso /path/to/source.iso \
  --workdir ./work \
  --iso-output ./custom-linux.iso \
  all
```

4. Deploy the generated ISO to a USB stick:

```bash
sudo ./scrips/st-usb.sh \
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
sudo ./scrips/st-usb.sh \
  --usb-drive /dev/sdX \
  --iso ./custom-linux.iso \
  --linux-size 4 \
  --encrypted-size 1 \
  --none-encrypted-size 1 \
  all
```

## ISO build workflow

The active sequence in `scrips/st-iso.sh` is:

```text
clean
prepare
extract
customize
make-iso
```

The full workflow can also be run as a single command:

```bash
sudo ./scrips/st-iso.sh all
```

## Boot the chroot directly in QEMU

After the ISO has been extracted and customized, you can test `work/chroot`
directly without rebuilding or booting the ISO:

```bash
sudo ./scrips/st-qemu-chroot.sh --workdir /work
```

The script copies the kernel and live initramfs from `work/image/antiX` into
`work/qemu-direct`, adds the matching 9p kernel modules, and replaces the
copied initramfs entry point with one that mounts `work/chroot` as the guest
root filesystem. The original initramfs and chroot are not rebuilt or replaced.
Use `--prepare-only` to create the QEMU files without starting the VM.
The host needs `cpio`, `unmkinitramfs`, `modinfo`, `modprobe`, and QEMU.

The guest accesses the host chroot read/write over 9p, so changes made in the
VM also affect `work/chroot`. The live-system startup performed by the original
initramfs is bypassed; this is a direct root-filesystem boot for testing, not an
equivalent boot of the finished live ISO.
The VM uses QEMU's SPICE display and the guest's `spice-vdagent` for clipboard
sharing. Clipboard integration is available in the graphical session; a text
TTY does not provide a graphical clipboard by itself.
At boot, the script sets QEMU's keyboard map to German and applies the German
`pc105`/`nodeadkeys` layout for X11 and the virtual console in the shared chroot.

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
sudo ./scrips/st-usb.sh --usb-drive /dev/sdX --iso ./custom-linux.iso --sizes 15,20,5 all
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

## Safe Stick frontend

`safe-stick/` is the Rust GUI frontend planned for the repository's `st-*` scripts. The goal is to make the ISO build, USB deployment, and related workflows available from one application, with configuration fields and an interactive terminal for command output and prompts.

The frontend is under development; the ISO **Extract** action runs the embedded `scripts/st-iso.sh` with the configured ISO, work directory, and output path. At build time, all Git-tracked files under `scripts/` are embedded, and the app restores that directory structure into a temporary directory at startup so the scripts can use their relative paths. Untracked files, such as downloaded build artifacts, are not embedded. Other GUI actions are not all connected yet, so the existing shell scripts remain the supported way to run the remaining workflows described above.

Build and run the GUI from the repository root with:

```bash
cargo run --manifest-path safe-stick/Cargo.toml
```

The About tab shows the frontend version from `safe-stick/Cargo.toml`.

## Notes

This repository is meant for building and customizing a live antiX/MX Linux environment. It is not a general-purpose package manager or a documentation project for every old helper script in the `archive/` folder.

## Todos

- Time is not correct in qemu
- ALT + TAB or WIN key caused lost control in qemu
- torbrowser-update
- veracrypt
