#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           OrionOS — Project Diagnostics                     ║
# ║  Checks structure, files, sizes, git status                 ║
# ╚══════════════════════════════════════════════════════════════╝
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

G='\033[0;32m'
R='\033[0;31m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${G}[OK]${NC} $1"; }
warn() { echo -e "  ${Y}[WARN]${NC} $1"; }
fail() { echo -e "  ${R}[FAIL]${NC} $1"; }

echo -e "${C}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${NC}           ${C}🔍 OrionOS Project Diagnostics${NC}                    ${C}║${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- 1. Структура ---
echo -e "${Y}📁 Structure Check${NC}"

for dir in config scripts src/overlay/opt/orionos/cores \
           src/overlay/opt/orionos/themes \
           src/overlay/opt/orionos/sources \
           src/overlay/opt/orionos/tools \
           src/overlay/opt/orionos/configs; do
    if [ -d "$dir" ]; then
        ok "Directory: $dir/"
    else
        warn "Missing: $dir/"
    fi
done

# --- 2. Критические файлы ---
echo ""
echo -e "${Y}📄 Critical Files${NC}"

for file in config/cores-whitelist.txt \
            userpatches/customize-image.sh \
            scripts/build.sh \
            scripts/compress.sh; do
    if [ -f "$file" ]; then
        size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
        ok "$file ($size)"
    else
        fail "$file MISSING!"
    fi
done

# --- 3. Ядра ---
echo ""
echo -e "${Y}🎮 Cores${NC}"

CORES_DIR="src/overlay/opt/orionos/cores"
if [ -d "$CORES_DIR" ]; then
    count=$(ls "$CORES_DIR"/*.so 2>/dev/null | wc -l)
    size=$(du -sh "$CORES_DIR" 2>/dev/null | awk '{print $1}')
    if [ "$count" -gt 0 ]; then
        ok "$count cores found ($size)"
    else
        fail "No cores in $CORES_DIR/"
    fi
else
    fail "Cores directory missing"
fi

# --- 4. Темы ---
echo ""
echo -e "${Y}🎨 Themes${NC}"

THEMES_DIR="src/overlay/opt/orionos/themes"
if [ -d "$THEMES_DIR" ]; then
    count=$(find "$THEMES_DIR" -maxdepth 1 -type d | wc -l)
    count=$((count - 1))  # exclude parent
    size=$(du -sh "$THEMES_DIR" 2>/dev/null | awk '{print $1}')
    if [ "$count" -gt 0 ]; then
        ok "$count themes found ($size)"
        for d in "$THEMES_DIR"/*; do
            [ -d "$d" ] || continue
            echo "       - $(basename "$d")"
        done
    else
        warn "No themes in $THEMES_DIR/"
    fi
else
    warn "Themes directory missing"
fi

# --- 5. Sources ---
echo ""
echo -e "${Y}📦 Sources${NC}"

SOURCES_DIR="src/overlay/opt/orionos/sources"
for src in EmulationStation PortMaster-GUI; do
    if [ -d "$SOURCES_DIR/$src/.git" ]; then
        ok "$src (git repo)"
    else
        warn "$src missing or not a git repo"
    fi
done

# --- 6. Armbian Build ---
echo ""
echo -e "${Y}🔨 Armbian Build${NC}"

if [ -d "armbian-build/.git" ]; then
    size=$(du -sh armbian-build 2>/dev/null | awk '{print $1}')
    ok "armbian-build/ present ($size)"
else
    warn "armbian-build/ not found (will be cloned on build)"
fi

# --- 7. Образы ---
echo ""
echo -e "${Y}💿 Images${NC}"

img_count=$(find . -maxdepth 1 -name "*.img" -o -name "*.img.tar.xz" 2>/dev/null | wc -l)
if [ "$img_count" -gt 0 ]; then
    ok "$img_count image(s) in root"
    find . -maxdepth 1 \( -name "*.img" -o -name "*.img.tar.xz" \) -exec ls -lh {} \;
else
    warn "No images built yet"
fi

# --- 8. Git ---
echo ""
echo -e "${Y}🌿 Git Status${NC}"

if [ -d ".git" ]; then
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    ok "Git repo on branch: $branch"

    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
    if [ "$untracked" -gt 0 ]; then
        warn "$untracked untracked files (check .gitignore)"
    else
        ok "No untracked files"
    fi
else
    warn "Not a git repository"
fi

# --- 9. Размер проекта ---
echo ""
echo -e "${Y}📊 Project Size${NC}"

if command -v du &>/dev/null; then
    total=$(du -sh "$ROOT_DIR" 2>/dev/null | awk '{print $1}')
    echo "  Total: $total"

    if [ -d "armbian-build" ]; then
        ab_size=$(du -sh armbian-build 2>/dev/null | awk '{print $1}')
        echo "  armbian-build: $ab_size"
    fi

    if [ -d "src/overlay/opt/orionos/cores" ]; then
        c_size=$(du -sh src/overlay/opt/orionos/cores 2>/dev/null | awk '{print $1}')
        echo "  cores: $c_size"
    fi
fi

echo ""
echo -e "${G}=== Diagnostics complete ===${NC}"
