#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS — Sync Resources                          ║
# ║  Downloads EmulationStation and PortMaster-GUI sources      ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCES_DIR="$ROOT_DIR/src/overlay/opt/orionos/sources"
mkdir -p "$SOURCES_DIR"

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

echo -e "${C}=== OrionOS Resource Sync ===${NC}"
echo ""

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

# EmulationStation
clone_or_update \
    "https://github.com/RetroPie/EmulationStation.git" \
    "$SOURCES_DIR/EmulationStation" \
    "EmulationStation"

# PortMaster-GUI
clone_or_update \
    "https://github.com/PortsMaster/PortMaster-GUI.git" \
    "$SOURCES_DIR/PortMaster-GUI" \
    "PortMaster-GUI"

echo ""
echo -e "${G}=== Resources synced ===${NC}"
