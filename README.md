# Creating and Deploying an MX Linux USB

This project creates a customized, hybrid-bootable MX Linux ISO and deploys it
to a USB drive. Customizations are performed inside an extracted chroot
filesystem. The USB deployment also creates an encrypted exFAT data partition
that can be unlocked on Linux and Windows with VeraCrypt.

## System Requirements

- Tested on Ubuntu 26.04
- A Debian-based Linux system, preferably MX Linux
- A valid MX Linux ISO, such as MX 25 Xfce x64
- Bash
- Root privileges; the script currently expects to be run with `sudo`
- Internet access for package installation inside the chroot
- Sufficient free disk space for the extracted filesystem and the rebuilt ISO
- Sufficient RAM and CPU time for SquashFS compression
- A USB drive with enough capacity for the Linux partition and data partition
- VeraCrypt for the USB deployment step

The host system must provide these commands:

- `apt-get`
- `bash`
- `chroot`
- `findmnt`
- `mount` and `umount`
- `realpath`
- `rsync`
- `md5sum`
- `mksquashfs` and `unsquashfs`
- `xorriso`
- `sudo`

The required packages `squashfs-tools`, `xorriso`, and `rsync` are installed by
`system_prepare`. The other commands are normally included in a standard
Debian or MX Linux installation. The deployment script additionally requires
`veracrypt`, `parted`, `partprobe`, `lsblk`, and `dd`.

## Usage

Show help:

```bash
./create-with-iso-mx.sh --help
```

The default ISO path is:

```text
/home/fsteinha/Downloads/MX-25_Xfce_x64.iso
```

You can specify a different ISO or working directory:

```bash
sudo ./create-with-iso-mx.sh \
  --iso /path/to/mx-linux.iso \
  --workdir ./mx-work all
```

## Commands

| Command | Description |
| --- | --- |
| `clean` | Delete the working directory after confirmation |
| `system_check` | Check required system commands |
| `system_prepare` | Install required system packages |
| `prepare` | Clean the working directory and prepare the system |
| `linuxfs` | Mount the ISO, copy files, and extract `linuxfs` |
| `customize` | Install packages in the chroot |
| `shell` | Open an interactive shell in the chroot |
| `new_mx_squashfs` | Unmount the chroot and create a new SquashFS |
| `create_final_iso` | Create the final bootable ISO |
| `all` | Run all build steps in sequence |

Commands can be run individually, for example:

```bash
sudo ./create-with-iso-mx.sh system_check
sudo ./create-with-iso-mx.sh system_prepare
sudo ./create-with-iso-mx.sh prepare
```

## Interactive Chroot Shell

After `linuxfs`, you can open a shell inside the extracted MX filesystem:

```bash
sudo ./create-with-iso-mx.sh shell
```

Use `exit` to leave the shell. The mounts created by the script are then cleaned
up automatically.

## Complete Workflow

```bash
sudo ./create-with-iso-mx.sh all
```

`all` runs these steps:

```text
prepare
linuxfs
customize
new_mx_squashfs
create_final_iso
```

The finished ISO is created at:

```text
./mx-work/custom-mx-linux.iso
```

## Deploying to USB

After creating the ISO, use `deploy-to-usb.sh` to write it to a USB drive:

```bash
sudo ./deploy-to-usb.sh
```

The script uses an ISO path below the invoking user's home directory by default:

```text
$HOME/mx-work/custom-mx-linux.iso
```

Adjust `ISO_PATH` in `deploy-to-usb.sh` if the ISO is stored elsewhere. The
script asks you to select the target drive and type `yes` as a final confirmation.

To update only the existing Linux/ISO partition after changing the extracted
filesystem, first rebuild the SquashFS and ISO:

```bash
sudo ./create-with-iso-mx.sh \
  --workdir /home/fsteinha/project/livelinux \
  new_mx_squashfs
sudo ./create-with-iso-mx.sh \
  --workdir /home/fsteinha/project/livelinux \
  create_final_iso
```

Then update partition 1 without changing the partition table or partition 2:

```bash
sudo ./deploy-to-usb.sh \
  --iso /home/fsteinha/project/livelinux/custom-mx-linux.iso \
  --target-drive /dev/sdX \
  update_linux_partition
```

Replace `/dev/sdX` with the whole USB disk, not its partition. The existing
`all` step remains destructive and recreates the complete USB layout.

The USB drive is configured as follows:

| Partition | Purpose |
| --- | --- |
| Partition 1 | Custom MX Linux ISO image |
| Partition 2 | VeraCrypt-encrypted exFAT data partition |

The Linux partition is `15 GB` by default. The data partition is `10 GB` by
default and uses the remaining space when `--encrypted-size 0` is selected.
These values can be changed with the command-line options of
`deploy-to-usb.sh`.

### Important Warning

Deployment completely erases the selected USB drive, including its partition
table and all existing data. Check the selected device carefully before
confirming. Do not select your system disk.

The VeraCrypt password is required later to unlock the encrypted data
partition. Windows computers need VeraCrypt to access this partition.

When installing `cryptsetup`, the following warning may appear in the chroot:
`Couldn't determine root device`. This is expected in this environment as long
as the package installation completes successfully.
