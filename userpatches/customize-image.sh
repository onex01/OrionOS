#!/usr/bin/env bash
# =============================================================================
#  OrionOS customize-image.sh  —  v3.0
#
#  Armbian вызывает этот скрипт внутри chroot целевого rootfs.
#  Переменные $BOARD, $RELEASE, $DISTRIBUTION экспортируются системой сборки.
#  Файлы из userpatches/overlay/ копируются в / ДО запуска этого скрипта.
#
#  BUILD_TYPE: "release" (по умолчанию) | "debug"
#    release: SSH отключён, минимальный образ
#    debug:   SSH включён, verbose, root-доступ
# =============================================================================
set -eo pipefail

# ── Переменные (BUILD_TYPE патчится CI или build.sh перед сборкой) ──────────
ORION_VERSION="0.1.0"
BUILD_TYPE="release"       # ← патчится скриптом сборки
ORION_USER="orion"
ORION_ROMS_PATH="/roms"
CORES_DEST="/usr/lib/aarch64-linux-gnu/libretro"   # стандартный путь Debian

# ── Логирование ──────────────────────────────────────────────────────────────
LOG="/var/log/orion-customize.log"
exec > >(tee -a "$LOG") 2>&1

log()  { echo "[OrionOS][$(date +%H:%M:%S)] $*"; }
warn() { echo "[OrionOS][WARN][$(date +%H:%M:%S)] $*" >&2; }

# Мягкая установка — предупреждает, но не прерывает сборку
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@" 2>&1 || warn "apt: часть пакетов не установлена: $*"
}

log "=== OrionOS v${ORION_VERSION} (${BUILD_TYPE}) customize-image.sh START ==="
log "Board=${BOARD:-unknown}  Release=${RELEASE:-unknown}"

# ── 0. Базовые пакеты ────────────────────────────────────────────────────────
log "[0] Установка базовых пакетов..."
apt-get update -qq

# Обязательный минимум
apt_install \
    curl wget ca-certificates \
    sudo \
    network-manager \
    bluez bluez-tools \
    alsa-utils \
    python3 python3-evdev \
    jq rsync \
    exfatprogs dosfstools e2fsprogs ntfs-3g \
    zram-tools \
    xserver-xorg-core xserver-xorg-input-libinput xinit \
    plymouth plymouth-themes \
    openssh-server

# Debug-дополнения
if [[ "$BUILD_TYPE" == "debug" ]]; then
    apt_install htop nano vim strace lsof \
                usbutils pciutils i2c-tools \
                v4l-utils alsa-utils gpiod
fi

# ── 1. RetroArch (есть в Debian Bookworm) ───────────────────────────────────
log "[1] Установка RetroArch..."
apt_install retroarch || warn "retroarch недоступен через apt"

# ── 2. Учётная запись пользователя ──────────────────────────────────────────
log "[2] Настройка пользователя ${ORION_USER}..."
if ! id "$ORION_USER" &>/dev/null; then
    useradd -m -s /bin/bash \
        -G sudo,audio,video,input,plugdev,netdev,bluetooth,dialout,render \
        "$ORION_USER"
fi
echo "${ORION_USER}:orion" | chpasswd
# ── FIX: убрали passwd -e — принудительная смена пароля вешала систему ──────

echo "${ORION_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/orion
chmod 0440 /etc/sudoers.d/orion

# Hostname
echo "orionos" > /etc/hostname
sed -i "s/127\.0\.1\.1.*/127.0.1.1\torionos/" /etc/hosts 2>/dev/null || \
    echo "127.0.1.1 orionos" >> /etc/hosts

# ── 3. Автовход на tty1 ─────────────────────────────────────────────────────
# FIX: вместо отключения getty@tty1 — настраиваем автовход.
# Если ES не запустится — пользователь увидит shell, а не зависание.
log "[3] Настройка автовхода на tty1..."

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${ORION_USER} --noclear %I \$TERM
EOF

# Запуск ES через bash_profile (надёжнее чем прямой systemd-сервис для X11)
mkdir -p "/home/${ORION_USER}"
cat > "/home/${ORION_USER}/.bash_profile" << 'PROFILE'
# OrionOS: запуск EmulationStation на tty1 после автовхода
if [[ -z "$DISPLAY" && "$(tty)" == "/dev/tty1" ]]; then
    exec /usr/local/bin/orion-start
fi
PROFILE
chown "${ORION_USER}:${ORION_USER}" "/home/${ORION_USER}/.bash_profile"

# orion-start: запускает ES или даёт shell
cat > /usr/local/bin/orion-start << 'OSTART'
#!/usr/bin/env bash
# OrionOS launcher — запускает EmulationStation или даёт shell при ошибке
ES_BIN=""
for b in /usr/bin/es-de /usr/bin/emulationstation /usr/local/bin/emulationstation; do
    [[ -x "$b" ]] && { ES_BIN="$b"; break; }
done

if [[ -z "$ES_BIN" ]]; then
    echo ""
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║  OrionOS — EmulationStation не найден ║"
    echo "  ║  Подключитесь по SSH и установите ES  ║"
    echo "  ║  или запустите: sudo enable-ssh.sh    ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo ""
    exec /bin/bash
fi

# Запуск через startx (без display manager, напрямую на KMS)
exec startx /usr/local/bin/orion-xinitrc -- :0 -nocursor vt1
OSTART
chmod +x /usr/local/bin/orion-start

# xinitrc для ES
cat > /usr/local/bin/orion-xinitrc << 'XINITRC'
#!/usr/bin/env bash
export HOME="/home/orion"
export XDG_RUNTIME_DIR="/run/user/$(id -u orion)"
export DISPLAY=:0

# Отключаем screensaver/DPMS
xset s off
xset -dpms
xset s noblank

for b in /usr/bin/es-de /usr/bin/emulationstation /usr/local/bin/emulationstation; do
    [[ -x "$b" ]] && exec "$b"
done
XINITRC
chmod +x /usr/local/bin/orion-xinitrc

# XDG runtime dir для orion
cat > /etc/tmpfiles.d/orion-runtime.conf << EOF
d /run/user 0755 root root -
d /run/user/$(id -u "$ORION_USER" 2>/dev/null || echo 1000) 0700 ${ORION_USER} ${ORION_USER} -
d /run/orion 0755 root root -
EOF

# ── 4. EmulationStation DE (ES-DE) ─────────────────────────────────────────
log "[4] Установка EmulationStation DE..."

install_esde() {
    # Способ 1: apt (если добавлен репозиторий)
    if apt_install emulationstation-de 2>/dev/null; then
        log "ES-DE установлен через apt"
        return 0
    fi

    # Способ 2: скачать .deb с GitLab releases
    log "Пробуем загрузить ES-DE .deb с GitLab..."
    local API="https://gitlab.com/api/v4/projects/413288/releases"
    local TAG
    TAG=$(curl -sf --max-time 30 "$API" 2>/dev/null | \
          python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['tag_name'])" \
          2>/dev/null || echo "")

    if [[ -n "$TAG" ]]; then
        local VER="${TAG#v}"
        local DEB="emulationstation-de_${VER}_arm64.deb"
        local URL="https://gitlab.com/es-de/emulationstation-de/-/releases/${TAG}/downloads/${DEB}"
        if wget -q --timeout=120 -O "/tmp/${DEB}" "$URL" 2>/dev/null; then
            dpkg -i "/tmp/${DEB}" 2>/dev/null || apt-get -f install -y -qq 2>/dev/null || true
            rm -f "/tmp/${DEB}"
            if command -v es-de &>/dev/null || command -v emulationstation &>/dev/null; then
                log "ES-DE ${VER} установлен"
                return 0
            fi
        fi
    fi

    # Способ 3: проверить overlay (если бинарник положен заранее)
    if [[ -f /opt/orionos/bin/emulationstation ]]; then
        install -m 755 /opt/orionos/bin/emulationstation /usr/local/bin/emulationstation
        log "ES взят из overlay"
        return 0
    fi

    warn "EmulationStation не установлен. Система загрузится в shell."
    warn "При наличии интернета: sudo apt install emulationstation-de"
    return 1
}

install_esde || true

# ── 5. libretro ядра ────────────────────────────────────────────────────────
log "[5] Установка libretro ядер..."
mkdir -p "$CORES_DEST"

# Список приоритетных ядер (устанавливаем всегда если возможно через apt)
apt_install \
    libretro-nestopia \
    libretro-snes9x \
    libretro-genesis-plus-gx \
    libretro-pcsx-rearmed \
    libretro-mgba \
    libretro-fbneo \
    libretro-mame2003-plus \
    2>/dev/null || true

# Дополнительные ядра: сначала из overlay, потом с nightly
OVERLAY_CORES="/opt/orionos/cores"
if ls "${OVERLAY_CORES}"/*.so &>/dev/null 2>&1; then
    log "Используем предзагруженные ядра из overlay ($(ls "${OVERLAY_CORES}"/*.so | wc -l) шт.)"
    cp "${OVERLAY_CORES}"/*.so "$CORES_DEST/" 2>/dev/null || true
else
    log "Overlay ядра не найдены, скачиваем с libretro nightly..."
    NIGHTLY="https://buildbot.libretro.com/nightly/linux/aarch64/latest"
    declare -a DL_CORES=(
        "nestopia_libretro"
        "snes9x_libretro"
        "genesis_plus_gx_libretro"
        "pcsx_rearmed_libretro"
        "mgba_libretro"
        "melonds_libretro"
        "mednafen_pce_fast_libretro"
        "mednafen_wswan_libretro"
        "fbneo_libretro"
        "mame2003_plus_libretro"
        "mupen64plus_next_libretro"
        "gambatte_libretro"
        "sameboy_libretro"
        "ppsspp_libretro"
        "scummvm_libretro"
        "prboom_libretro"
        "tyrquake_libretro"
    )
    for core in "${DL_CORES[@]}"; do
        local_path="${CORES_DEST}/${core}.so"
        [[ -f "$local_path" ]] && continue
        if wget -q --timeout=60 -O "/tmp/${core}.zip" \
                "${NIGHTLY}/${core}.so.zip" 2>/dev/null; then
            unzip -o -q "/tmp/${core}.zip" -d "$CORES_DEST" 2>/dev/null || true
            rm -f "/tmp/${core}.zip"
            log "  [+] ${core}"
        else
            warn "  [-] ${core} (недоступно)"
        fi
    done
fi

chmod 644 "${CORES_DEST}"/*.so 2>/dev/null || true
log "Ядер установлено: $(ls "${CORES_DEST}"/*.so 2>/dev/null | wc -l)"

# ── 6. Конфигурация EmulationStation ────────────────────────────────────────
log "[6] Конфигурация EmulationStation..."

ES_CFGDIR="/home/${ORION_USER}/.config/emulationstation"
mkdir -p "$ES_CFGDIR" /etc/emulationstation

# Копируем es_systems.xml из overlay если есть, иначе генерируем базовый
if [[ -f /opt/orionos/configs/es_systems.cfg ]]; then
    cp /opt/orionos/configs/es_systems.cfg /etc/emulationstation/es_systems.xml
    log "  es_systems.xml взят из overlay"
else
    warn "  es_systems.cfg не найден в overlay, используем встроенный минимум"
    cat > /etc/emulationstation/es_systems.xml << 'ESXML'
<?xml version="1.0" encoding="UTF-8"?>
<systemList>
  <system>
    <name>nes</name><fullname>Nintendo Entertainment System</fullname>
    <path>/roms/nes</path><extension>.nes .fds .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so %ROM%</command>
    <platform>nes</platform><theme>nes</theme>
  </system>
  <system>
    <name>snes</name><fullname>Super Nintendo</fullname>
    <path>/roms/snes</path><extension>.smc .sfc .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform><theme>snes</theme>
  </system>
  <system>
    <name>megadrive</name><fullname>Sega Mega Drive</fullname>
    <path>/roms/megadrive</path><extension>.md .gen .bin .smd .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>megadrive</platform><theme>megadrive</theme>
  </system>
  <system>
    <name>psx</name><fullname>Sony PlayStation</fullname>
    <path>/roms/psx</path><extension>.bin .cue .img .iso .pbp .chd</extension>
    <command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/pcsx_rearmed_libretro.so %ROM%</command>
    <platform>psx</platform><theme>psx</theme>
  </system>
  <system>
    <name>gba</name><fullname>Game Boy Advance</fullname>
    <path>/roms/gba</path><extension>.gba .GBA .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mgba_libretro.so %ROM%</command>
    <platform>gba</platform><theme>gba</theme>
  </system>
  <system>
    <name>ports</name><fullname>Ports &amp; Tools</fullname>
    <path>/roms/ports</path><extension>.sh .SH</extension>
    <command>bash %ROM%</command>
    <platform>ports</platform><theme>ports</theme>
  </system>
</systemList>
ESXML
fi

# Права
chown -R "${ORION_USER}:${ORION_USER}" "/home/${ORION_USER}" "$ES_CFGDIR" 2>/dev/null || true

# ── 7. RetroArch конфиг ─────────────────────────────────────────────────────
log "[7] Конфигурация RetroArch..."
mkdir -p /etc/retroarch /etc/retroarch/config \
         "/home/${ORION_USER}/.config/retroarch"

cat > /etc/retroarch/retroarch.cfg << 'RACFG'
# OrionOS RetroArch config — оптимизировано для H618 / Mali G31
video_driver = "gl"
video_fullscreen = "true"
video_threaded = "true"
video_vsync = "true"
video_scale_integer = "true"
video_aspect_ratio_auto = "true"
audio_driver = "alsa"
audio_latency = "64"
audio_rate_control = "true"
input_driver = "udev"
input_max_users = "4"
input_autodetect_enable = "true"
libretro_directory = "/usr/lib/aarch64-linux-gnu/libretro"
savefile_directory = "/roms/saves"
savestate_directory = "/roms/states"
screenshot_directory = "/roms/screenshots"
menu_driver = "ozone"
rewind_enable = "false"
video_shader_enable = "false"
RACFG

ln -sf /etc/retroarch/retroarch.cfg \
    "/home/${ORION_USER}/.config/retroarch/retroarch.cfg" 2>/dev/null || true

# ── 8. Директории ROM ────────────────────────────────────────────────────────
log "[8] Создание директорий ROM..."
for sys in nes snes n64 gb gbc gba nds megadrive mastersystem gamegear \
           segacd sega32x psx psp pcengine arcade neogeo \
           atari2600 atari2600 atari5200 atari7800 atarilynx c64 amiga \
           dos msx zxspectrum dreamcast saturn \
           doom quake scummvm pico8 \
           saves states screenshots ports \
           videos audio; do
    mkdir -p "${ORION_ROMS_PATH}/${sys}"
done
mkdir -p /roms2
chown -R "${ORION_USER}:${ORION_USER}" "${ORION_ROMS_PATH}" /roms2

# ── 9. fstab оптимизации ────────────────────────────────────────────────────
log "[9] Оптимизация fstab..."
sed -i 's|\(ext4\s\+\)defaults|\1defaults,noatime,lazytime,commit=60|' /etc/fstab || true
sed -i '/\bswap\b/d' /etc/fstab
rm -f /var/swap
systemctl disable dphys-swapfile 2>/dev/null || true

# ── 10. Kernel modules ─────────────────────────────────────────────────────
log "[10] Настройка kernel modules..."
cat > /etc/modules-load.d/orion.conf << 'EOF'
panfrost
gpu_sched
hid_nintendo
hid_sony
ntfs3
exfat
joydev
uinput
EOF

cat > /etc/modprobe.d/orion-hid.conf << 'EOF'
options hid_nintendo jc_player_leds=1
options hid_nintendo home_led_brightness=25
EOF

# ── 11. zram swap ───────────────────────────────────────────────────────────
log "[11] Настройка zram..."
cat > /etc/default/zramswap << 'EOF'
ALGO=zstd
SIZE=512
PRIORITY=100
EOF

# ── 12. udev правила ────────────────────────────────────────────────────────
log "[12] Установка udev правил..."

cat > /etc/udev/rules.d/60-orion-gpu.rules << 'EOF'
SUBSYSTEM=="devfreq", KERNEL=="1800000.gpu", ATTR{governor}="simple_ondemand"
EOF

cat > /etc/udev/rules.d/61-orion-cpu.rules << 'EOF'
SUBSYSTEM=="cpu", ACTION=="add|change", ATTR{cpufreq/scaling_governor}="schedutil"
EOF

cat > /etc/udev/rules.d/65-orion-usb.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", \
    TAG+="systemd", ENV{SYSTEMD_WANTS}="orion-usb-mount@%k.service"
ACTION=="remove", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", \
    RUN+="/bin/systemctl stop orion-usb-mount@%k.service"
EOF

# ── 13. systemd сервисы ─────────────────────────────────────────────────────
log "[13] Установка systemd сервисов..."

# USB mount шаблон
cat > /etc/systemd/system/orion-usb-mount@.service << 'EOF'
[Unit]
Description=OrionOS USB ROM mount for %i
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/orion/mount-usb.sh %i add
ExecStop=/usr/lib/orion/mount-usb.sh %i remove
EOF

# Bluetooth геймпад
cat > /etc/systemd/system/orion-bluetooth.service << 'EOF'
[Unit]
Description=OrionOS BT Gamepad Auto-Pairing
After=bluetooth.service
Requires=bluetooth.service

[Service]
ExecStart=/usr/lib/orion/bt-gamepad.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

# oga_events для PortMaster
cat > /etc/systemd/system/oga-events.service << 'EOF'
[Unit]
Description=OrionOS oga_events gamepad translator
After=systemd-udev-settle.service

[Service]
ExecStart=/usr/bin/python3 /usr/lib/orion/oga-events.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Firstboot (resize + начальная настройка)
cat > /etc/systemd/system/orion-firstboot.service << 'EOF'
[Unit]
Description=OrionOS First Boot Setup
ConditionPathExists=/opt/orionos/.firstboot-needed
After=network.target
Before=getty@tty1.service

[Service]
Type=oneshot
ExecStart=/opt/orionos/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ── 14. Скрипты в /usr/lib/orion ────────────────────────────────────────────
log "[14] Установка системных скриптов..."
mkdir -p /usr/lib/orion

# USB mount
cat > /usr/lib/orion/mount-usb.sh << 'MOUNT'
#!/usr/bin/env bash
set -euo pipefail
DEV="${1:?}"; ACTION="${2:-add}"
MOUNT_BASE="/roms2"; MOUNT_PT="${MOUNT_BASE}/${DEV}"; DEVPATH="/dev/${DEV}"
ORION_USER="orion"

if [[ "$ACTION" == "remove" ]]; then
    umount -l "$MOUNT_PT" 2>/dev/null || true
    rmdir "$MOUNT_PT" 2>/dev/null || true
    exit 0
fi
[[ -b "$DEVPATH" ]] || exit 1

FSTYPE=$(blkid -o value -s TYPE "$DEVPATH" 2>/dev/null || echo "auto")
UID_VAL=$(id -u "$ORION_USER" 2>/dev/null || echo 1000)
GID_VAL=$(id -g "$ORION_USER" 2>/dev/null || echo 1000)
mkdir -p "$MOUNT_PT"

case "$FSTYPE" in
    vfat|fat32) OPTS="rw,noatime,uid=${UID_VAL},gid=${GID_VAL},fmask=0022,dmask=0022" ;;
    exfat)      OPTS="rw,noatime,uid=${UID_VAL},gid=${GID_VAL},fmask=0022,dmask=0022" ;;
    ntfs)       OPTS="rw,noatime,uid=${UID_VAL},gid=${GID_VAL}"; FSTYPE="ntfs3" ;;
    *)          OPTS="rw,noatime" ;;
esac

mount -t "$FSTYPE" -o "$OPTS" "$DEVPATH" "$MOUNT_PT" 2>/dev/null || \
    mount -o "ro,noatime" "$DEVPATH" "$MOUNT_PT" 2>/dev/null || \
    { rmdir "$MOUNT_PT"; exit 1; }

# Создаём директорию OrionOS на флешке если её нет
mkdir -p "${MOUNT_PT}/OrionOS/roms" \
         "${MOUNT_PT}/OrionOS/videos" \
         "${MOUNT_PT}/OrionOS/audio" 2>/dev/null || true
chown -R "$UID_VAL:$GID_VAL" "${MOUNT_PT}/OrionOS" 2>/dev/null || true

# Симлинки rom-директорий с флешки в /roms
if [[ -d "${MOUNT_PT}/OrionOS/roms" ]]; then
    for d in "${MOUNT_PT}/OrionOS/roms"/*/; do
        [[ -d "$d" ]] || continue
        sys="$(basename "$d")"
        [[ ! -e "/roms/${sys}_usb" ]] && ln -sfn "$d" "/roms/${sys}_usb" || true
    done
fi

logger -t orion-usb "Смонтировано ${DEV} (${FSTYPE}) в ${MOUNT_PT}"
MOUNT
chmod +x /usr/lib/orion/mount-usb.sh

# BT gamepad
cat > /usr/lib/orion/bt-gamepad.sh << 'BT'
#!/usr/bin/env bash
set -euo pipefail
KNOWN="/var/lib/orion/bt-known"; mkdir -p /var/lib/orion; touch "$KNOWN"

bluetoothctl power on 2>/dev/null || true
bluetoothctl agent NoInputNoOutput 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true
bluetoothctl pairable on 2>/dev/null || true

# Переподключаем известные устройства
while IFS=' ' read -r mac _rest; do
    [[ -n "$mac" ]] && bluetoothctl connect "$mac" 2>/dev/null || true
done < "$KNOWN"

# Цикл сканирования
while true; do
    bluetoothctl scan on & SCAN=$!; sleep 30; kill $SCAN 2>/dev/null || true
    bluetoothctl scan off 2>/dev/null || true
    while IFS= read -r line; do
        mac=$(echo "$line" | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}' || true)
        [[ -z "$mac" ]] && continue
        grep -qiF "$mac" "$KNOWN" 2>/dev/null && continue
        # Проверяем класс устройства (0x0500 = HID / Peripheral)
        cls=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Class:/{print $2}' || echo "")
        [[ -z "$cls" ]] && continue
        cls_int=$(( 16#${cls//0x/} ))
        (( (cls_int & 0x1F00) == 0x0500 )) || continue
        name=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Name:/{$1="";print}' | xargs || echo "Gamepad")
        bluetoothctl pair "$mac" 2>/dev/null && \
        bluetoothctl trust "$mac" 2>/dev/null && \
        bluetoothctl connect "$mac" 2>/dev/null && \
        echo "$mac $name" >> "$KNOWN" && \
        logger -t orion-bt "Paired: $name ($mac)"
    done < <(bluetoothctl devices 2>/dev/null || true)
    sleep 10
done
BT
chmod +x /usr/lib/orion/bt-gamepad.sh

# oga_events
cat > /usr/lib/orion/oga-events.py << 'OGA'
#!/usr/bin/env python3
"""OrionOS oga_events — evdev gamepad translator for PortMaster"""
import asyncio, evdev, signal, sys, logging
from evdev import ecodes as e, UInput

logging.basicConfig(format="%(asctime)s [oga_events] %(message)s", level=logging.INFO)
log = logging.getLogger()

BUTTON_MAP = {
    e.BTN_SOUTH: e.KEY_X,    e.BTN_EAST: e.KEY_Z,
    e.BTN_NORTH: e.KEY_S,    e.BTN_WEST: e.KEY_A,
    e.BTN_TL:    e.KEY_E,    e.BTN_TR:   e.KEY_T,
    e.BTN_SELECT: e.KEY_RIGHTCTRL, e.BTN_START: e.KEY_ENTER,
    e.BTN_MODE:  e.KEY_ESC,
}

def find_gamepad():
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
            if e.EV_KEY in d.capabilities() and e.BTN_SOUTH in d.capabilities()[e.EV_KEY]:
                return d
        except Exception:
            pass
    return None

async def main():
    gp = None
    while not gp:
        gp = find_gamepad()
        if not gp:
            await asyncio.sleep(5)
    log.info(f"Gamepad: {gp.name}")
    ui = UInput({e.EV_KEY: list(BUTTON_MAP.values())}, name="orion-oga-events")
    signal.signal(signal.SIGTERM, lambda *_: (ui.close(), sys.exit(0)))
    async for ev in gp.async_read_loop():
        if ev.type == e.EV_KEY and ev.code in BUTTON_MAP:
            ui.write(e.EV_KEY, BUTTON_MAP[ev.code], ev.value)
            ui.syn()

asyncio.run(main())
OGA
chmod +x /usr/lib/orion/oga-events.py

# ── 15. SSH настройка по BUILD_TYPE ─────────────────────────────────────────
log "[15] Настройка SSH (BUILD_TYPE=${BUILD_TYPE})..."

if [[ "$BUILD_TYPE" == "debug" ]]; then
    log "  DEBUG: SSH включён по умолчанию"
    systemctl enable ssh.service 2>/dev/null || true
    # В debug-сборке root-логин разрешён для отладки
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
    echo "root:orionos_debug" | chpasswd 2>/dev/null || true
else
    log "  RELEASE: SSH отключён (пользователь включает вручную)"
    systemctl disable ssh.service 2>/dev/null || true
fi

# Скрипт включения SSH (для release-сборки)
cat > /usr/local/bin/enable-ssh.sh << 'ENABLESSH'
#!/usr/bin/env bash
# OrionOS — включение SSH
set -e
echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║      OrionOS — Включение SSH              ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

systemctl enable ssh.service
systemctl start ssh.service

# Показываем IP и данные для подключения
IP=$(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)
echo ""
echo "  SSH включён!"
echo "  Подключение: ssh orion@${IP:-<IP_адрес>}"
echo "  Пароль: orion (смените после первого входа)"
echo ""
echo "  Для отключения: sudo systemctl disable --now ssh"
echo ""
ENABLESSH
chmod +x /usr/local/bin/enable-ssh.sh

# ── 16. Активация сервисов ───────────────────────────────────────────────────
log "[16] Активация сервисов..."

systemctl enable oga-events.service       2>/dev/null || true
systemctl enable orion-bluetooth.service  2>/dev/null || true
systemctl enable bluetooth.service        2>/dev/null || true
systemctl enable NetworkManager.service   2>/dev/null || true
systemctl enable orion-firstboot.service  2>/dev/null || true
systemctl enable zramswap.service         2>/dev/null || true

# Отключаем ненужное для консоли
for svc in apt-daily apt-daily-upgrade unattended-upgrades \
           ModemManager avahi-daemon cups; do
    systemctl disable "${svc}.service" 2>/dev/null || true
    systemctl mask "${svc}.service" 2>/dev/null || true
done

# ── 17. Ports / Tools скрипты ────────────────────────────────────────────────
log "[17] Создание Ports скриптов..."
mkdir -p /roms/ports

cat > "/roms/ports/WiFi Setup.sh" << 'P'
#!/usr/bin/env bash
nmtui-connect
P
chmod +x "/roms/ports/WiFi Setup.sh"

cat > "/roms/ports/SSH Enable.sh" << 'P'
#!/usr/bin/env bash
sudo /usr/local/bin/enable-ssh.sh
P
chmod +x "/roms/ports/SSH Enable.sh"

cat > "/roms/ports/System Info.sh" << 'P'
#!/usr/bin/env bash
source /etc/orion/release 2>/dev/null || true
echo "OrionOS ${ORION_VERSION:-?} (${BUILD_TYPE:-release})"
echo "Board: $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo '?')"
for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/temp" 2>/dev/null || echo 0)
    echo "Thermal $(basename $z): $((t/1000))°C"
done
echo "RAM: $(free -h | awk '/Mem:/{print $3"/"$2}')"
echo "ROM: $(df -h /roms 2>/dev/null | awk 'NR==2{print $3"/"$2}')"
echo "IP: $(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1)"
read -rp "Нажмите Enter..."
P
chmod +x "/roms/ports/System Info.sh"

chown -R "${ORION_USER}:${ORION_USER}" /roms

# ── 18. Firstboot скрипт ────────────────────────────────────────────────────
log "[18] Firstboot скрипт..."
mkdir -p /opt/orionos

cat > /opt/orionos/firstboot.sh << 'FB'
#!/usr/bin/env bash
# OrionOS — первая загрузка
set -e
FLAG="/opt/orionos/.firstboot-needed"
[[ ! -f "$FLAG" ]] && exit 0

LOG="/var/log/orion-firstboot.log"
exec >> "$LOG" 2>&1

echo "[firstboot] $(date) — начало"

# Расширение файловой системы
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
if [[ -n "$ROOT_DEV" ]]; then
    DISK=$(echo "$ROOT_DEV" | sed 's/p\?[0-9]*$//')
    PART=$(echo "$ROOT_DEV" | grep -o '[0-9]*$')
    parted -s "$DISK" resizepart "$PART" 100% 2>/dev/null && \
    resize2fs "$ROOT_DEV" 2>/dev/null && \
    echo "[firstboot] rootfs расширен" || true
fi

# Создаём /roms директории если их нет
for sys in nes snes gba megadrive psx ports saves states; do
    mkdir -p "/roms/$sys"
done
chown -R orion:orion /roms

rm -f "$FLAG"
echo "[firstboot] $(date) — готово"
FB
chmod +x /opt/orionos/firstboot.sh

# Флаг для первой загрузки
touch /opt/orionos/.firstboot-needed

# ── 19. Метаданные релиза ────────────────────────────────────────────────────
log "[19] Метаданные..."
mkdir -p /etc/orion
cat > /etc/orion/release << EOF
ORION_VERSION="${ORION_VERSION}"
BUILD_TYPE="${BUILD_TYPE}"
ORION_BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORION_BOARD="${BOARD:-orangepizero3}"
EOF

# issue (приветствие в консоли)
cat > /etc/issue << EOF
OrionOS ${ORION_VERSION} (${BUILD_TYPE})
Orange Pi Zero 3 — Allwinner H618
EOF

# ── 20. Чистка ──────────────────────────────────────────────────────────────
log "[20] Очистка..."
apt-get autoremove -y -qq 2>/dev/null || true
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* /tmp/*.zip /tmp/*.deb /tmp/*.AppImage \
       /tmp/squashfs-root /tmp/ra-install

log "=== OrionOS customize-image.sh DONE. Build: ${BUILD_TYPE} ==="
