#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS — DISTCLEAN (Remove Everything)           ║
# ║  Removes cores, themes, sources, armbian-build, images      ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
NC='\033[0m'

echo -e "${R}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${R}║${NC}  ${R}⚠  DANGER: DISTCLEAN — This will remove ALL downloaded    ${NC}  ${R}║${NC}"
echo -e "${R}║${NC}  ${R}    files: cores, themes, sources, armbian-build, images.  ${NC}  ${R}║${NC}"
echo -e "${R}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -rp "Type 'yes' to confirm complete destruction: " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${G}Aborted. Nothing was removed.${NC}"
    exit 0
fi

echo ""
echo -e "${Y}Removing...${NC}"

# 1. Cores
if [ -d "src/overlay/opt/orionos/cores" ]; then
    echo -e "  ${R}[DEL]${NC} src/overlay/opt/orionos/cores/*.so"
    rm -f src/overlay/opt/orionos/cores/*.so
    rm -f src/overlay/opt/orionos/cores/*.zip
fi

# 2. Themes
if [ -d "src/overlay/opt/orionos/themes" ]; then
    echo -e "  ${R}[DEL]${NC} src/overlay/opt/orionos/themes/*"
    rm -rf src/overlay/opt/orionos/themes/*
fi

# 3. Sources (ES, PortMaster, etc)
if [ -d "src/overlay/opt/orionos/sources" ]; then
    echo -e "  ${R}[DEL]${NC} src/overlay/opt/orionos/sources/*"
    rm -rf src/overlay/opt/orionos/sources/*
fi

# 4. armbian-build
if [ -d "armbian-build" ]; then
    echo -e "  ${R}[DEL]${NC} armbian-build/"
    rm -rf armbian-build
fi

# 5. Images & archives
for pattern in "*.img" "*.img.tar.xz" "*.img.gz"; do
    for f in $pattern; do
        [ -f "$f" ] || continue
        echo -e "  ${R}[DEL]${NC} $f"
        rm -f "$f"
    done
done

# 6. Logs & temp
rm -f *.log
rm -rf build/ dist/ output/ tmp/ temp/

echo ""
echo -e "${G}=== Distclean finished. Project is now pristine. ===${NC}"
