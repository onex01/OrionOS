#!/bin/bash
# Авторасширение rootfs при первой загрузке
set -e

FLAG="/opt/orionos/.resize-needed"
[ ! -f "$FLAG" ] && exit 0

ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_PART=$(echo "$ROOT_DEV" | grep -o '[0-9]*$')
DISK_DEV=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')

echo "[Resize] Resizing $ROOT_DEV..."
parted -s "$DISK_DEV" resizepart "$ROOT_PART" 100%
resize2fs "$ROOT_DEV"
rm -f "$FLAG"
echo "[Resize] Done."
