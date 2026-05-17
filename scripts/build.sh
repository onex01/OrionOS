#!/bin/bash
# =============================================================================
#  OrionOS Build Script v3.0 — локальная сборка
#
#  Использование:
#    bash scripts/build.sh                    # release-сборка
#    bash scripts/build.sh debug              # debug-сборка (SSH включён)
#    bash scripts/build.sh release trixie     # release на trixie
#
#  Требования:
#    - Ubuntu 22.04/24.04 или Debian Bookworm
#    - Минимум 50 GB свободного места
#    - sudo (Armbian использует loop-устройства)
#    - git, wget, curl
#
#  Для локальной сборки с предзагруженными ядрами:
#    bash scripts/sync-cores.sh    ← сначала
#    bash scripts/build.sh         ← потом
# =============================================================================
set -eo pipefail

# ── Аргументы ────────────────────────────────────────────────────────────────
BUILD_TYPE="${1:-release}"    # release | debug
RELEASE="${2:-bookworm}"      # bookworm | trixie | noble

# Проверяем аргументы
if [[ "$BUILD_TYPE" != "release" && "$BUILD_TYPE" != "debug" ]]; then
    echo "ERROR: BUILD_TYPE должен быть 'release' или 'debug'"
    echo "Usage: $0 [release|debug] [bookworm|trixie]"
    exit 1
fi

# ── Конфигурация ──────────────────────────────────────────────────────────────
BOARD="orangepizero3"
BRANCH="current"
# ВАЖНО: версия Armbian должна совпадать с тегом в build.yml (armbian/build@v25.02)
ARMBIAN_BRANCH="v25.02"
ARMBIAN_REPO="https://github.com/armbian/build"

# Директории
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_OVERLAY="$ROOT_DIR/src/overlay"
ARMBUILD_DIR="$ROOT_DIR/armbian-build"

# Цвета
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${C}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${Y}[WARN]${NC} $*" >&2; }
fail() { echo -e "${R}[ERROR]${NC} $*" >&2; exit 1; }

echo -e "${C}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║${NC}       ${Y}OrionOS Build Script v3.0${NC}                      ${C}║${NC}"
echo -e "${C}║${NC}  Board: ${BOARD}  Type: ${BUILD_TYPE}  Distro: ${RELEASE}  ${C}║${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Проверка системы ─────────────────────────────────────────────────────────
log "Проверка окружения..."
[[ "$(id -u)" -eq 0 ]] && fail "Не запускайте от root. sudo использует Armbian сам."
command -v git  &>/dev/null || fail "git не установлен"
command -v wget &>/dev/null || fail "wget не установлен"

# ── Версия из orion.conf ─────────────────────────────────────────────────────
ORION_VERSION="0.1.0"
[[ -f "$ROOT_DIR/orion.conf" ]] && \
    ORION_VERSION=$(grep '^ORION_VERSION' "$ROOT_DIR/orion.conf" | \
                   head -1 | cut -d'"' -f2 || echo "0.1.0")
if [[ "$BUILD_TYPE" == "debug" ]]; then
    ORION_VERSION="${ORION_VERSION}-debug.$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)"
fi
log "Версия: OrionOS v${ORION_VERSION} [${BUILD_TYPE}]"

# ── [0] Pruning cores ────────────────────────────────────────────────────────
log "[0/7] Pruning cores по whitelist..."
if [[ -f "$ROOT_DIR/scripts/prune-cores.sh" ]]; then
    bash "$ROOT_DIR/scripts/prune-cores.sh" || warn "prune-cores завершился с ошибкой"
else
    warn "prune-cores.sh не найден"
fi

# ── [1] Armbian build framework ──────────────────────────────────────────────
log "[1/7] Armbian build framework (branch: ${ARMBIAN_BRANCH})..."
if [[ ! -d "$ARMBUILD_DIR/.git" ]]; then
    log "  Клонируем armbian/build..."
    git clone --depth 1 --branch "$ARMBIAN_BRANCH" "$ARMBIAN_REPO" "$ARMBUILD_DIR"
else
    log "  Обновляем armbian/build..."
    git -C "$ARMBUILD_DIR" fetch --depth 1 origin "$ARMBIAN_BRANCH" 2>/dev/null || \
        warn "  fetch не удался, используем текущую версию"
    git -C "$ARMBUILD_DIR" checkout "$ARMBIAN_BRANCH" 2>/dev/null || true
fi

# ── [2] Ядра (опционально, из sync-cores.sh) ─────────────────────────────────
log "[2/7] Проверка ядер..."
CORES_DIR="$SRC_OVERLAY/opt/orionos/cores"
if ls "${CORES_DIR}"/*.so &>/dev/null 2>&1; then
    COUNT=$(ls "${CORES_DIR}"/*.so 2>/dev/null | wc -l)
    SIZE=$(du -sh "$CORES_DIR" 2>/dev/null | awk '{print $1}')
    log "  ✓ ${COUNT} ядер в overlay (${SIZE})"
else
    warn "  Ядра не найдены в overlay. customize-image.sh скачает их во время сборки."
    warn "  Для офлайн-сборки запустите сначала: bash scripts/sync-cores.sh"
fi

# ── [3] Темы (опционально) ───────────────────────────────────────────────────
log "[3/7] Проверка тем..."
THEMES_DIR="$SRC_OVERLAY/opt/orionos/themes"
if ls -d "${THEMES_DIR}"/*/  &>/dev/null 2>&1; then
    COUNT=$(find "$THEMES_DIR" -maxdepth 1 -type d | tail -n +2 | wc -l)
    log "  ✓ ${COUNT} тем в overlay"
else
    warn "  Темы не найдены. Для установки: bash scripts/sync-themes.sh"
fi

# ── [4] Подготовка userpatches ───────────────────────────────────────────────
log "[4/7] Подготовка userpatches..."

# Создаём структуру userpatches внутри armbian-build
mkdir -p "$ARMBUILD_DIR/userpatches/overlay"

# Копируем overlay (без .so и .git для скорости, .so прописаны отдельно)
log "  Копируем src/overlay/ → userpatches/overlay/"
rsync -a --exclude='*.git' \
    "$SRC_OVERLAY/" "$ARMBUILD_DIR/userpatches/overlay/"

# Если есть .so ядра — копируем их тоже
if ls "${CORES_DIR}"/*.so &>/dev/null 2>&1; then
    log "  Копируем ядра в overlay..."
    mkdir -p "$ARMBUILD_DIR/userpatches/overlay/opt/orionos/cores"
    cp "${CORES_DIR}"/*.so "$ARMBUILD_DIR/userpatches/overlay/opt/orionos/cores/"
fi

# Копируем и патчим customize-image.sh
log "  Патчим customize-image.sh (version=${ORION_VERSION}, build_type=${BUILD_TYPE})"
cp "$ROOT_DIR/userpatches/customize-image.sh" \
   "$ARMBUILD_DIR/userpatches/customize-image.sh"
sed -i "s/^ORION_VERSION=.*/ORION_VERSION=\"${ORION_VERSION}\"/" \
    "$ARMBUILD_DIR/userpatches/customize-image.sh"
sed -i "s/^BUILD_TYPE=.*/BUILD_TYPE=\"${BUILD_TYPE}\"/" \
    "$ARMBUILD_DIR/userpatches/customize-image.sh"
chmod +x "$ARMBUILD_DIR/userpatches/customize-image.sh"

# Kernel config (если есть)
if [[ -f "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" ]]; then
    mkdir -p "$ARMBUILD_DIR/userpatches/config/kernel"
    cp "$ROOT_DIR/config/kernel/linux-sunxi64-current.config" \
       "$ARMBUILD_DIR/userpatches/config/kernel/"
    log "  Kernel config скопирован"
fi

# ── [5] Сборка ───────────────────────────────────────────────────────────────
log "[5/7] Запуск Armbian build..."
echo ""
echo -e "${Y}  Начинается сборка. Это займёт 30-90 минут.${NC}"
echo -e "${Y}  Логи: $ARMBUILD_DIR/output/debug/${NC}"
echo ""

cd "$ARMBUILD_DIR"

# compile.sh автоматически подхватывает userpatches/customize-image.sh
# Не передаём CUSTOMIZE_SCRIPT — используем стандартный механизм Armbian
./compile.sh \
    BOARD="$BOARD" \
    BRANCH="$BRANCH" \
    RELEASE="$RELEASE" \
    BUILD_MINIMAL=yes \
    KERNEL_CONFIGURE=no \
    EXTRA_ROOTFS_MIB_SIZE=800 \
    FORCE_USE_RAMDISK=no \
    2>&1 | tee "$ROOT_DIR/build-${BUILD_TYPE}.log"

BUILD_EXIT=${PIPESTATUS[0]}
cd "$ROOT_DIR"

if [[ $BUILD_EXIT -ne 0 ]]; then
    fail "Armbian build завершился с ошибкой (код ${BUILD_EXIT}). Лог: build-${BUILD_TYPE}.log"
fi

# ── [6] Поиск и переименование образа ───────────────────────────────────────
log "[6/7] Поиск образа..."
IMAGE=$(find "$ARMBUILD_DIR/output/images" -name "*.img" -type f 2>/dev/null | head -1)
if [[ -z "$IMAGE" ]]; then
    fail "Образ не найден в $ARMBUILD_DIR/output/images/"
fi
log "  Найден: $IMAGE"

# Переименовываем в OrionOS-формат
OUT_NAME="OrionOS-${ORION_VERSION}-${BUILD_TYPE}-${BOARD}"
OUT_DIR="$ROOT_DIR/output"
mkdir -p "$OUT_DIR"
cp "$IMAGE" "${OUT_DIR}/${OUT_NAME}.img"
log "  Скопирован: ${OUT_DIR}/${OUT_NAME}.img"

# ── [7] Сжатие ───────────────────────────────────────────────────────────────
log "[7/7] Сжатие образа..."
XZ_OPT="-T0 -6" xz -v "${OUT_DIR}/${OUT_NAME}.img"
sha256sum "${OUT_DIR}/${OUT_NAME}.img.xz" > "${OUT_DIR}/${OUT_NAME}.sha256"

echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${G}║${NC}  ✓ Сборка завершена успешно!                          ${G}║${NC}"
echo -e "${G}║${NC}  Образ: output/${OUT_NAME}.img.xz               ${G}║${NC}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
ls -lh "${OUT_DIR}/${OUT_NAME}".*
