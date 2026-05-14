#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS Build System — Main Menu                  ║
# ║           Universal wrapper for all operations              ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

# Цвета
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
NC='\033[0m'

header() {
    clear
    echo -e "${C}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}           ${Y}🚀  OrionOS Build System v8.0${NC}                      ${C}║${NC}"
    echo -e "${C}║${NC}      ${B}Orange Pi Zero 3 — Retro Gaming OS${NC}                     ${C}║${NC}"
    echo -e "${C}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Проверяем dialog
USE_DIALOG=0
if command -v dialog &>/dev/null; then
    USE_DIALOG=1
fi

show_menu() {
    if [ "$USE_DIALOG" -eq 1 ]; then
        choice=$(dialog --clear --backtitle "OrionOS Build System" \
            --title "Main Menu" \
            --menu "Select operation:" 18 60 10 \
            1 "🎮  Sync Cores (download libretro cores)" \
            2 "📦  Sync Resources (ES + PortMaster)" \
            3 "🎨  Sync Themes (5 ES themes)" \
            4 "🔨  Build Image (Armbian + overlay)" \
            5 "🧹  Clean Build (keep armbian-build?)" \
            6 "💥  Distclean (remove EVERYTHING)" \
            7 "🔍  Project Diagnostics" \
            8 "📋  Show Project Structure" \
            9 "❌  Exit" \
            2>&1 >/dev/tty)
    else
        header
        echo -e "${Y}Select operation:${NC}"
        echo ""
        echo -e "  ${G}1${NC}) 🎮  Sync Cores          — download libretro cores"
        echo -e "  ${G}2${NC}) 📦  Sync Resources      — EmulationStation + PortMaster"
        echo -e "  ${G}3${NC}) 🎨  Sync Themes         — download 5 ES themes"
        echo -e "  ${G}4${NC}) 🔨  Build Image         — build Armbian image"
        echo -e "  ${G}5${NC}) 🧹  Clean Build         — clean artifacts"
        echo -e "  ${G}6${NC}) 💥  Distclean           — remove everything"
        echo -e "  ${G}7${NC}) 🔍  Diagnostics         — check project health"
        echo -e "  ${G}8${NC}) 📋  Show Structure      — display project tree"
        echo -e "  ${G}9${NC}) ❌  Exit"
        echo ""
        read -rp "Enter choice [1-9]: " choice
    fi
}

while true; do
    show_menu
    case "$choice" in
        1)
            header
            echo -e "${C}▶ Running: scripts/sync-cores.sh${NC}"
            bash "$ROOT_DIR/scripts/sync-cores.sh"
            echo -e "${G}✔ Done.${NC}"
            read -rp "Press Enter to continue..."
            ;;
        2)
            header
            echo -e "${C}▶ Running: scripts/sync-resources.sh${NC}"
            bash "$ROOT_DIR/scripts/sync-resources.sh"
            echo -e "${G}✔ Done.${NC}"
            read -rp "Press Enter to continue..."
            ;;
        3)
            header
            echo -e "${C}▶ Running: scripts/sync-themes.sh${NC}"
            bash "$ROOT_DIR/scripts/sync-themes.sh"
            echo -e "${G}✔ Done.${NC}"
            read -rp "Press Enter to continue..."
            ;;
        4)
            header
            echo -e "${C}▶ Running: scripts/build.sh${NC}"
            bash "$ROOT_DIR/scripts/build.sh"
            echo -e "${G}✔ Build complete.${NC}"
            read -rp "Press Enter to continue..."
            ;;
        5)
            header
            echo -e "${C}▶ Running: scripts/clean.sh${NC}"
            bash "$ROOT_DIR/scripts/clean.sh"
            read -rp "Press Enter to continue..."
            ;;
        6)
            header
            echo -e "${R}▶ Running: scripts/distclean.sh${NC}"
            bash "$ROOT_DIR/scripts/distclean.sh"
            read -rp "Press Enter to continue..."
            ;;
        7)
            header
            echo -e "${C}▶ Running: scripts/diagnose-project.sh${NC}"
            bash "$ROOT_DIR/scripts/diagnose-project.sh"
            read -rp "Press Enter to continue..."
            ;;
        8)
            header
            echo -e "${C}▶ Project Structure:${NC}"
            echo ""
            if command -v tree &>/dev/null; then
                tree -L 3 -I 'armbian-build|*.so|*.zip|*.img' "$ROOT_DIR"
            else
                find "$ROOT_DIR" -maxdepth 3 -not -path '*/armbian-build/*' -not -name '*.so' -not -name '*.zip' -not -name '*.img' | head -60
            fi
            echo ""
            read -rp "Press Enter to continue..."
            ;;
        9|""|q|Q)
            header
            echo -e "${G}👋 Goodbye!${NC}"
            exit 0
            ;;
        *)
            header
            echo -e "${R}Invalid choice: $choice${NC}"
            sleep 1
            ;;
    esac
done
