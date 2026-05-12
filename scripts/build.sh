#!/bin/bash
# OrionOS - fully automated build script (fetches all sources)
set -e

# --- Configuration ---
ARMBIAN_REPO="https://github.com/armbian/build"
ARMBIAN_BRANCH="main"
BOARD="orangepizero3"
BRANCH="current"
RELEASE="bookworm"

# Sources URLs
EMULATIONSTATION_REPO="https://github.com/RetroPie/EmulationStation.git"
PORTMASTER_REPO="https://github.com/PortsMaster/PortMaster-GUI.git"
THEME_CARBON_REPO="https://github.com/RetroPie/es-theme-carbon.git"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_OVERLAY="$ROOT_DIR/src/overlay"
SOURCES_DIR="$SRC_OVERLAY/opt/orionos/sources"
ARMBUILD_DIR="$ROOT_DIR/armbian-build"

# --- Helper function ---
clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    if [ ! -d "$target_dir/.git" ]; then
        echo "Cloning $repo_url into $target_dir..."
        git clone --depth 1 "$repo_url" "$target_dir"
    else
        echo "Updating $target_dir..."
        cd "$target_dir"
        git pull --ff-only
        cd - >/dev/null
    fi
}

# --- Main ---
echo "=== OrionOS Build Script ==="
echo "Root: $ROOT_DIR"
echo ""

# 1. Clone Armbian if needed
if [ ! -d "$ARMBUILD_DIR" ]; then
    echo "[1/6] Cloning Armbian build repository..."
    git clone --depth 1 --branch "$ARMBIAN_BRANCH" "$ARMBIAN_REPO" "$ARMBUILD_DIR"
else
    echo "[1/6] Armbian repository exists, updating..."
    cd "$ARMBUILD_DIR"
    git pull --ff-only
    cd - >/dev/null
fi

# 2. Fetch game sources into overlay
echo "[2/6] Fetching EmulationStation..."
clone_or_update "$EMULATIONSTATION_REPO" "$SOURCES_DIR/EmulationStation"

echo "[3/6] Fetching PortMaster-GUI..."
clone_or_update "$PORTMASTER_REPO" "$SOURCES_DIR/PortMaster-GUI"

echo "[4/6] Fetching es-theme-carbon..."
clone_or_update "$THEME_CARBON_REPO" "$SOURCES_DIR/es-theme-carbon"

# 3. Prepare userpatches
echo "[5/6] Preparing userpatches..."
mkdir -p "$ARMBUILD_DIR/userpatches/overlay"
cp -r "$SRC_OVERLAY/." "$ARMBUILD_DIR/userpatches/overlay/"
cp "$ROOT_DIR/src/customize-image.sh" "$ARMBUILD_DIR/userpatches/customize-image.sh"
chmod +x "$ARMBUILD_DIR/userpatches/customize-image.sh"

# Kernel config
if [ -f "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" ]; then
    mkdir -p "$ARMBUILD_DIR/userpatches/config/kernel"
    cp "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" "$ARMBUILD_DIR/userpatches/config/kernel/"
fi

# 4. Build
echo "[6/6] Starting Armbian build..."
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

# 5. Compress
IMAGE=$(find "$ARMBUILD_DIR/output/images" -name "*.img" -type f | head -n 1)
if [ -z "$IMAGE" ]; then
    echo "ERROR: No image found!"
    exit 1
fi
bash "$ROOT_DIR/scripts/compress.sh" "$IMAGE"

echo ""
echo "=== Build finished successfully! ==="
echo "Compressed image: ${IMAGE}.tar.xz"