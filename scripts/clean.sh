#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS — Clean Build Artifacts                   ║
# ║  Removes images, logs, temp files. Asks about armbian-build ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

echo -e "${C}=== OrionOS Clean ===${NC}"
echo ""

# 1. Образы
deleted=0
for pattern in "*.img" "*.img.tar.xz" "*.img.gz" "*.img.bz2"; do
    for f in $pattern; do
        [ -f "$f" ] || continue
        echo -e "  ${Y}[DEL]${NC} $f"
        rm -f "$f"
        ((deleted++)) || true
    done
done

# 2. Логи
for f in *.log /tmp/orionos-*.log 2>/dev/null; do
    [ -f "$f" ] || continue
    echo -e "  ${Y}[DEL]${NC} $f"
    rm -f "$f"
    ((deleted++)) || true
done

# 3. Временные файлы
for d in build/ dist/ output/ tmp/ temp/; do
    if [ -d "$d" ]; then
        echo -e "  ${Y}[DEL]${NC} directory: $d/"
        rm -rf "$d"
        ((deleted++)) || true
    fi
done

# 4. Кэши apt внутри overlay (если есть)
if [ -d "src/overlay/var/cache/apt/archives" ]; then
    echo -e "  ${Y}[DEL]${NC} apt cache in overlay"
    rm -rf src/overlay/var/cache/apt/archives/* 2>/dev/null || true
fi

# 5. armbian-build — спрашиваем!
echo ""
if [ -d "$ROOT_DIR/armbian-build" ]; then
    size=$(du -sh "$ROOT_DIR/armbian-build" 2>/dev/null | awk '{print $1}')
    echo -e "${Y}⚠ Found armbian-build/ (${size})${NC}"
    echo "  This folder contains the Armbian build system (~2-3 GB)."
    echo "  Downloading it again takes 10-20 minutes."
    echo ""
    read -rp "  Remove armbian-build/ ? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo -e "  ${R}[DEL]${NC} Removing armbian-build/..."
        rm -rf "$ROOT_DIR/armbian-build"
        echo -e "  ${G}✔ armbian-build removed.${NC}"
    else
        echo -e "  ${G}✔ Keeping armbian-build/.${NC}"
    fi
fi

echo ""
echo -e "${G}=== Clean finished ===${NC}"
