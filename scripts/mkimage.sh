#!/bin/bash
# Создание .img из собранного rootfs (для быстрой итерации)
set -e

ROOTFS_DIR="$1"
OUTPUT="${2:-orionos-$(date +%Y%m%d).img}"
SIZE_MB="${3:-3072}"  # 3GB default

if [ -z "$ROOTFS_DIR" ] || [ ! -d "$ROOTFS_DIR" ]; then
    echo "Usage: $0 <rootfs-dir> [output.img] [size_mb]"
    exit 1
fi

echo "Creating $OUTPUT (${SIZE_MB}MB)..."
dd if=/dev/zero of="$OUTPUT" bs=1M count=$SIZE_MB status=progress

# Partition: 256MB boot + rest rootfs
parted -s "$OUTPUT" mklabel msdos
parted -s "$OUTPUT" mkpart primary fat32 1MiB 257MiB
parted -s "$OUTPUT" mkpart primary ext4 257MiB 100%
parted -s "$OUTPUT" set 1 boot on

LOOP=$(losetup -fP --show "$OUTPUT")
echo "Loop: $LOOP"

mkfs.vfat -F32 "${LOOP}p1"
mkfs.ext4 -O ^metadata_csum,^64bit "${LOOP}p2"

mkdir -p /tmp/orionos-boot /tmp/orionos-root
mount "${LOOP}p1" /tmp/orionos-boot
mount "${LOOP}p2" /tmp/orionos-root

# Copy rootfs
rsync -aHAX --exclude=/boot "$ROOTFS_DIR/" /tmp/orionos-root/
# Copy boot
rsync -aHAX "$ROOTFS_DIR/boot/" /tmp/orionos-boot/ 2>/dev/null || true

# Install bootloader (для H618 — u-boot вписывается в образ отдельно)
# Здесь заглушка — в реальности используй armbian-build u-boot
echo "Done. Install u-boot manually: dd if=u-boot.bin of=$OUTPUT bs=1k seek=8 conv=notrunc"

umount /tmp/orionos-boot /tmp/orionos-root
losetup -d "$LOOP"
rmdir /tmp/orionos-boot /tmp/orionos-root

echo "Created: $OUTPUT"