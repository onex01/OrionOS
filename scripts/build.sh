#!/bin/bash
# OrionOS Build Script v2.2 — uses new resource paths
set -e

# --- Configuration ---
ARMBIAN_REPO="https://github.com/armbian/build"
ARMBIAN_BRANCH="main"
BOARD="orangepizero3"
BRANCH="current"
RELEASE="bookworm"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_OVERLAY="$ROOT_DIR/src/overlay"
SOURCES_DIR="$SRC_OVERLAY/opt/orionos/sources"
THEMES_DIR="$SRC_OVERLAY/opt/orionos/themes"
ARMBUILD_DIR="$ROOT_DIR/armbian-build"

# --- Helper function ---
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    if [ -d "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
        echo "Removing non-git directory: $target_dir"
        rm -rf "$target_dir"
    fi
    if [ ! -d "$target_dir/.git" ]; then
        echo "Cloning $repo_url into $target_dir..."
        git clone --depth 1 "$repo_url" "$target_dir"
    else
        echo "Updating $target_dir..."
        cd "$target_dir"
        git pull --ff-only || echo "Pull failed, keeping current"
        cd - >/dev/null
    fi
}

# --- Main ---
echo "=== OrionOS Build Script v2.2 ==="
echo "Root: $ROOT_DIR"
echo ""

# 0. Prune cores before build
echo "[0/7] Pruning cores to whitelist..."
if [ -f "$ROOT_DIR/scripts/prune-cores.sh" ]; then
    bash "$ROOT_DIR/scripts/prune-cores.sh"
else
    echo "WARNING: prune-cores.sh not found, skipping..."
fi

# 1. Clone Armbian if needed
echo "[1/7] Armbian repository..."
if [ ! -d "$ARMBUILD_DIR" ]; then
    git clone --depth 1 --branch "$ARMBIAN_BRANCH" "$ARMBIAN_REPO" "$ARMBUILD_DIR"
else
    cd "$ARMBUILD_DIR"
    git pull --ff-only || echo "Armbian pull failed, keeping current"
    cd - >/dev/null
fi

# 2. Ensure resources exist
echo "[2/7] Checking resources..."
if [ ! -d "$SOURCES_DIR/EmulationStation/.git" ]; then
    echo "EmulationStation not found. Run: bash scripts/sync-resources.sh"
    exit 1
fi
if [ ! -d "$SOURCES_DIR/PortMaster-GUI/.git" ]; then
    echo "PortMaster-GUI not found. Run: bash scripts/sync-resources.sh"
    exit 1
fi

# 3. Ensure themes exist
echo "[3/7] Checking themes..."
if [ ! -d "$THEMES_DIR/carbon" ]; then
    echo "Theme 'carbon' not found. Run: bash scripts/sync-themes.sh"
    exit 1
fi

# 4. Prepare userpatches
echo "[4/7] Preparing userpatches..."
mkdir -p "$ARMBUILD_DIR/userpatches/overlay"
cp -r "$SRC_OVERLAY/." "$ARMBUILD_DIR/userpatches/overlay/"
cp "$ROOT_DIR/src/customize-image.sh" "$ARMBUILD_DIR/userpatches/customize-image.sh"
chmod +x "$ARMBUILD_DIR/userpatches/customize-image.sh"

# Kernel config
if [ -f "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" ]; then
    mkdir -p "$ARMBUILD_DIR/userpatches/config/kernel"
    cp "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" "$ARMBUILD_DIR/userpatches/config/kernel/"
fi

# 5. Build
echo "[5/7] Starting Armbian build..."
cd "$ARMBUILD_DIR"
./compile.sh \
    BOARD="$BOARD" \
    BRANCH="$BRANCH" \
    RELEASE="$RELEASE" \
    BUILD_MINIMAL=yes \
    KERNEL_CONFIGURE=no \
    EXTRA_ROOTFS_MIB_SIZE=800 \
    FORCE_USE_RAMDISK=no \
    CUSTOMIZE_SCRIPT="userpatches/customize-image.sh"
cd "$ROOT_DIR"

# 6. Compress
echo "[6/7] Compressing image..."
IMAGE=$(find "$ARMBUILD_DIR/output/images" -name "*.img" -type f | head -n 1)
if [ -z "$IMAGE" ]; then
    echo "ERROR: No image found!"
    exit 1
fi
bash "$ROOT_DIR/scripts/compress.sh" "$IMAGE"

echo ""
echo "=== Build finished successfully! ==="
echo "Compressed image: ${IMAGE}.tar.xz"
