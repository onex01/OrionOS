#!/bin/bash
# Compress image to tar.xz
if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-image.img>"
    exit 1
fi
IMAGE="$1"
echo "Compressing $IMAGE ..."
XZ_OPT=-9 tar -cJf "${IMAGE}.tar.xz" "$IMAGE"
echo "Created ${IMAGE}.tar.xz"