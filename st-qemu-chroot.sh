#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: st-qemu-chroot.sh [--workdir PATH] [--prepare-only]

Prepare a QEMU initramfs that mounts WORKDIR/chroot as its root filesystem.
The matching kernel and live initramfs are read from WORKDIR/image/antiX.

Options:
  --workdir PATH   Build directory (default: ./work)
  --prepare-only   Prepare workdir/qemu-direct without starting QEMU
  -h, --help       Show this help
EOF
}

WORK_DIR="./work"
PREPARE_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir)
            if [[ $# -lt 2 ]]; then
                printf '%s\n' "Missing path after --workdir." >&2
                exit 2
            fi
            WORK_DIR=$2
            shift 2
            ;;
        --prepare-only)
            PREPARE_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ $EUID -ne 0 && $PREPARE_ONLY -eq 0 ]]; then
    printf '%s\n' "Run this script with sudo; QEMU needs access to the root-owned chroot." >&2
    exit 1
fi

for command_name in cpio modinfo modprobe unmkinitramfs xz; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ $PREPARE_ONLY -eq 0 ]] && ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    printf '%s\n' "Required command not found: qemu-system-x86_64" >&2
    exit 1
fi

WORK_DIR=$(realpath -m "$WORK_DIR")
CHROOT_DIR="$WORK_DIR/chroot"
ANTI_X_DIR="$WORK_DIR/image/antiX"
QEMU_DIR="$WORK_DIR/qemu-direct"
KERNEL="$ANTI_X_DIR/vmlinuz"
INITRD="$ANTI_X_DIR/initrd.gz"

if [[ ! -d "$CHROOT_DIR" ]]; then
    printf 'Chroot directory not found: %s\n' "$CHROOT_DIR" >&2
    exit 1
fi
if [[ ! -f "$KERNEL" || ! -f "$INITRD" ]]; then
    printf 'Kernel or initramfs not found under %s; build/extract the ISO first.\n' "$ANTI_X_DIR" >&2
    exit 1
fi
if [[ "$CHROOT_DIR" == *","* ]]; then
    printf '%s\n' "The chroot path cannot contain commas (QEMU's 9p option syntax)." >&2
    exit 1
fi

shopt -s nullglob
MODULE_DIRS=("$CHROOT_DIR"/lib/modules/*)
if [[ ${#MODULE_DIRS[@]} -ne 1 ]]; then
    printf 'Expected one kernel module directory under %s/lib/modules, found %d.\n' \
        "$CHROOT_DIR" "${#MODULE_DIRS[@]}" >&2
    exit 1
fi
KERNEL_VERSION=${MODULE_DIRS[0]##*/}
NINEP_MODULE="$CHROOT_DIR/lib/modules/$KERNEL_VERSION/kernel/net/9p/9pnet_virtio.ko.xz"
if [[ ! -f "$NINEP_MODULE" ]]; then
    NINEP_MODULE="$CHROOT_DIR/lib/modules/$KERNEL_VERSION/kernel/net/9p/9pnet_virtio.ko"
fi
if [[ ! -f "$NINEP_MODULE" ]]; then
    printf 'The 9p virtio module is missing for kernel %s.\n' "$KERNEL_VERSION" >&2
    exit 1
fi
MODULE_VERMAGIC=$(modinfo -F vermagic "$NINEP_MODULE")
if [[ ${MODULE_VERMAGIC%% *} != "$KERNEL_VERSION" ]]; then
    printf 'Kernel module version mismatch: expected %s, found %s.\n' \
        "$KERNEL_VERSION" "${MODULE_VERMAGIC%% *}" >&2
    exit 1
fi

MODULE_DEPENDENCIES=$(
    {
        modprobe --show-depends --set-version "$KERNEL_VERSION" \
            --dirname "$CHROOT_DIR" 9p
        modprobe --show-depends --set-version "$KERNEL_VERSION" \
            --dirname "$CHROOT_DIR" 9pnet_virtio
    } | awk '!seen[$0]++'
)

mkdir -p "$QEMU_DIR"
TEMP_DIR=$(mktemp -d "$QEMU_DIR/.build.XXXXXX")
trap 'rm -rf -- "$TEMP_DIR"' EXIT
INITRAMFS_ROOT="$TEMP_DIR/root"
mkdir -p "$INITRAMFS_ROOT"

unmkinitramfs "$INITRD" "$INITRAMFS_ROOT"

if [[ ! -x "$INITRAMFS_ROOT/bin/busybox" || ! -x "$INITRAMFS_ROOT/bin/switch_root" ]]; then
    printf '%s\n' "The source initramfs lacks the BusyBox tools required for direct boot." >&2
    exit 1
fi

MODULES_DEST="$INITRAMFS_ROOT/lib/modules/$KERNEL_VERSION"
mkdir -p "$MODULES_DEST"
declare -A COPIED_MODULES=()
MODULE_RELATIVE_PATHS=()
while read -r operation module_path; do
    if [[ "$operation" != insmod ]]; then
        continue
    fi
    module_relative_path=${module_path#"$CHROOT_DIR/lib/modules/$KERNEL_VERSION/"}
    if [[ "$module_relative_path" == "$module_path" ]]; then
        printf 'Unexpected module path from modprobe: %s\n' "$module_path" >&2
        exit 1
    fi
    if [[ -n "${COPIED_MODULES[$module_relative_path]:-}" ]]; then
        continue
    fi
    COPIED_MODULES[$module_relative_path]=1
    mkdir -p "$MODULES_DEST/$(dirname "$module_relative_path")"
    if [[ "$module_relative_path" == *.xz ]]; then
        module_relative_path=${module_relative_path%.xz}
        xz -dc "$module_path" > "$MODULES_DEST/$module_relative_path"
    else
        cp -a "$module_path" "$MODULES_DEST/$module_relative_path"
    fi
    MODULE_RELATIVE_PATHS+=("$module_relative_path")
done <<< "$MODULE_DEPENDENCIES"

cat > "$INITRAMFS_ROOT/init" <<'INIT'
#!/bin/busybox sh

PATH=/bin:/sbin
export PATH

fail() {
    echo "Direct QEMU boot failed: $*" >/dev/console
    exec /bin/busybox sh
}

mkdir -p /dev /proc /sys /newroot

mount -t devtmpfs devtmpfs /dev || fail "cannot mount /dev"
mount -t proc proc /proc || fail "cannot mount /proc"
mount -t sysfs sysfs /sys || fail "cannot mount /sys"

INIT
for module_relative_path in "${MODULE_RELATIVE_PATHS[@]}"; do
    module_name=${module_relative_path##*/}
    module_name=${module_name%.ko}
    printf 'insmod /lib/modules/%s/%s || fail "cannot load %s"\n' \
        "$KERNEL_VERSION" "$module_relative_path" "$module_name"
done >> "$INITRAMFS_ROOT/init"
cat >> "$INITRAMFS_ROOT/init" <<'INIT'
mount -t 9p -o trans=virtio,version=9p2000.L,cache=loose chroot /newroot ||
    fail "cannot mount the shared chroot; check QEMU's 9p device"

mkdir -p /newroot/dev /newroot/proc /newroot/sys /newroot/run
mount --move /dev /newroot/dev || fail "cannot move /dev"
mount --move /proc /newroot/proc || fail "cannot move /proc"
mount --move /sys /newroot/sys || fail "cannot move /sys"
mount -t tmpfs -o mode=755 tmpfs /newroot/run || fail "cannot mount /run"

exec /bin/switch_root /newroot /lib/sysvinit/init
INIT
chmod 0755 "$INITRAMFS_ROOT/init"

cp -a "$KERNEL" "$QEMU_DIR/vmlinuz"
MICROCODE_DIR="$INITRAMFS_ROOT/kernel/x86/microcode"
if [[ -d "$MICROCODE_DIR" ]]; then
    EARLY_ROOT="$TEMP_DIR/early"
    mkdir -p "$EARLY_ROOT/kernel/x86"
    cp -a "$MICROCODE_DIR" "$EARLY_ROOT/kernel/x86/"
    rm -rf -- "$MICROCODE_DIR"
    rmdir "$INITRAMFS_ROOT/kernel/x86" "$INITRAMFS_ROOT/kernel" 2>/dev/null || true
    (
        cd "$EARLY_ROOT"
        find . -print0 | cpio --null -o --format=newc --owner=0:0 --quiet
    ) > "$TEMP_DIR/early.cpio"
fi
(
    cd "$INITRAMFS_ROOT"
    find . -print0 | cpio --null -o --format=newc --owner=0:0 --quiet
) > "$TEMP_DIR/main.cpio"
if [[ -f "$TEMP_DIR/early.cpio" ]]; then
    cat "$TEMP_DIR/early.cpio" "$TEMP_DIR/main.cpio" > "$TEMP_DIR/initrd.img"
else
    mv "$TEMP_DIR/main.cpio" "$TEMP_DIR/initrd.img"
fi
mv "$TEMP_DIR/initrd.img" "$QEMU_DIR/initrd.img"

printf 'Prepared direct-boot files in %s\n' "$QEMU_DIR"
printf 'The guest root is shared read/write with %s.\n' "$CHROOT_DIR"

if [[ $PREPARE_ONLY -eq 1 ]]; then
    exit 0
fi

QEMU_ARGS=(
    -enable-kvm
    -m 4G
    -smp 4
    -kernel "$QEMU_DIR/vmlinuz"
    -initrd "$QEMU_DIR/initrd.img"
    -append "console=ttyS0,115200n8 console=tty0 init=/lib/sysvinit/init"
    -virtfs "local,path=$CHROOT_DIR,mount_tag=chroot,security_model=none,id=chroot"
)

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    if qemu-system-x86_64 -display help 2>&1 | grep -qi gtk; then
        QEMU_ARGS+=(-display gtk)
    elif qemu-system-x86_64 -display help 2>&1 | grep -qi sdl; then
        QEMU_ARGS+=(-display sdl)
    else
        QEMU_ARGS+=(-nographic)
    fi
else
    QEMU_ARGS+=(-nographic)
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
