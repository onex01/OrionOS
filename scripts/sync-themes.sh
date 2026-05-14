#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS — Sync EmulationStation Themes              ║
# ║  Downloads 5 popular themes for ES                            ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

THEMES_DIR="$ROOT_DIR/src/overlay/opt/orionos/themes"
mkdir -p "$THEMES_DIR"

# Цвета
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

echo -e "${C}=== OrionOS Theme Sync ===${NC}"
echo ""

# Список тем: name|repo_url
declare -a THEMES=(
    "carbon|https://github.com/RetroPie/es-theme-carbon.git"
    "epicnoir|https://github.com/RetroPie/es-theme-epicnoir.git"
    "chicuelo|https://github.com/chicueloarcade/es-theme-chicuelo.git"
    "snes-mini|https://github.com/RetroPie/es-theme-snes-mini.git"
    "simple|https://github.com/RetroPie/es-theme-simple.git"
)

clone_or_update() {
    local repo_url="$1"
    local target_dir="$2"
    local name="$3"

    if [ -d "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
        echo -e "  ${Y}[WARN]${NC} $name exists but is not a git repo. Removing..."
        rm -rf "$target_dir"
    fi

    if [ ! -d "$target_dir/.git" ]; then
        echo -e "  ${G}[CLONE]${NC} $name"
        git clone --depth 1 "$repo_url" "$target_dir"
    else
        echo -e "  ${G}[PULL]${NC} $name"
        cd "$target_dir"
        git pull --ff-only || echo "    (pull failed, keeping current)"
        cd - >/dev/null
    fi
}

for entry in "${THEMES[@]}"; do
    IFS='|' read -r name url <<< "$entry"
    clone_or_update "$url" "$THEMES_DIR/$name" "$name"
done

echo ""
echo -e "${G}=== Themes synced ===${NC}"
echo "Installed themes:"
for d in "$THEMES_DIR"/*; do
    [ -d "$d" ] || continue
    size=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    echo "  $(basename "$d") ($size)"
done
