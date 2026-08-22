# Creating an MX Linux ISO

This project creates a customized, hybrid-bootable ISO from an MX Linux ISO.
Customizations are performed inside an extracted chroot filesystem.

## Requirements

- MX Linux ISO
- Bash
- `sudo`
- Root privileges
- Internet access for package installation

The required tools `squashfs-tools`, `xorriso`, and `rsync` are installed by
`system_prepare`.

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

When installing `cryptsetup`, the following warning may appear in the chroot:
`Couldn't determine root device`. This is expected in this environment as long
as the package installation completes successfully.
