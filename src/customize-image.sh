#!/usr/bin/env bash
# =============================================================================
#  OrionOS customize-image.sh
#  Place this file at: userpatches/customize-image.sh
#
#  Armbian calls this script automatically during image build, already inside
#  the target rootfs chroot.  The $BOARD, $RELEASE, $DISTRIBUTION variables
#  are exported by the build system.
#
#  Static files in userpatches/overlay/ are copied to / by Armbian BEFORE
#  this script runs — so you can reference them directly.
# =============================================================================
set -euo pipefail

# ── Version (patched by CI) ───────────────────────────────────────────────────
ORION_VERSION="0.1.0"
ORION_USER="orion"
ORION_ROMS_PATH="/roms"

# ── Logging ───────────────────────────────────────────────────────────────────
LOG="/var/log/orion-customize.log"
exec > >(tee -a "$LOG") 2>&1

log()  { echo "[OrionOS][$(date +%H:%M:%S)] $*"; }
warn() { echo "[OrionOS][WARN] $*" >&2; }
die()  { echo "[OrionOS][ERROR] $*" >&2; exit 1; }

# Non-fatal apt install — warns but doesn't abort the whole build
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@" 2>&1 || warn "apt: some packages failed: $*"
}

log "=== OrionOS v${ORION_VERSION} customize-image.sh START ==="
log "Board: ${BOARD:-unknown}  Release: ${RELEASE:-unknown}"

# ── 0. Base packages ──────────────────────────────────────────────────────────
log "Installing base packages..."
apt-get update -qq
apt_install \
    curl wget ca-certificates \
    sudo \
    network-manager \
    bluez bluez-tools \
    alsa-utils \
    python3 python3-evdev \
    jq rsync \
    exfatprogs dosfstools e2fsprogs \
    zram-tools \
    xserver-xorg-core xinit \
    plymouth plymouth-themes

# ── 1. User account ───────────────────────────────────────────────────────────
log "Creating user ${ORION_USER}..."
if ! id "$ORION_USER" &>/dev/null; then
    useradd -m -s /bin/bash \
        -G sudo,audio,video,input,plugdev,netdev,bluetooth,dialout \
        "$ORION_USER"
fi
echo "${ORION_USER}:orion" | chpasswd
passwd -e "$ORION_USER"   # force password change on first login
echo "${ORION_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/orion
chmod 0440 /etc/sudoers.d/orion

# ── 2. Directories ────────────────────────────────────────────────────────────
log "Creating ROM directories..."
for sys in nes snes megadrive psx gba nds pce wonderswan ports saves states screenshots; do
    mkdir -p "${ORION_ROMS_PATH}/${sys}"
done
mkdir -p /roms2 /etc/orion /var/lib/orion /usr/lib/orion
chown -R "${ORION_USER}:${ORION_USER}" "${ORION_ROMS_PATH}"

# ── 3. fstab optimisations ────────────────────────────────────────────────────
log "Patching fstab..."
sed -i 's|\(ext4\s\+\)defaults|\1defaults,noatime,lazytime,commit=60|' /etc/fstab || true
# Disable SD-card swap; zram replaces it
sed -i '/\bswap\b/d' /etc/fstab
rm -f /var/swap
systemctl disable dphys-swapfile 2>/dev/null || true

# ── 4. Kernel modules ─────────────────────────────────────────────────────────
log "Configuring kernel modules..."
cat > /etc/modules-load.d/orion.conf <<'EOF'
panfrost
gpu_sched
hid_nintendo
hid_sony
ntfs3
exfat
joydev
uinput
EOF

cat > /etc/modprobe.d/orion-hid.conf <<'EOF'
options hid_nintendo jc_player_leds=1
options hid_nintendo home_led_brightness=25
EOF

# ── 5. zram swap ─────────────────────────────────────────────────────────────
log "Configuring zram..."
cat > /etc/default/zramswap <<'EOF'
ALGO=zstd
SIZE=512
PRIORITY=100
EOF

# ── 6. udev rules ─────────────────────────────────────────────────────────────
log "Installing udev rules..."
cat > /etc/udev/rules.d/60-orion-gpu.rules <<'EOF'
SUBSYSTEM=="devfreq", KERNEL=="1800000.gpu", ATTR{governor}="simple_ondemand"
EOF

cat > /etc/udev/rules.d/61-orion-cpu.rules <<'EOF'
SUBSYSTEM=="cpu", ACTION=="add|change", ATTR{cpufreq/scaling_governor}="schedutil"
EOF

cat > /etc/udev/rules.d/62-orion-thermal.rules <<'EOF'
SUBSYSTEM=="thermal", KERNEL=="thermal_zone0", ATTR{policy}="step_wise"
EOF

cat > /etc/udev/rules.d/65-orion-usb-storage.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", \
    TAG+="systemd", ENV{SYSTEMD_WANTS}="orion-usb-mount@%k.service"
ACTION=="remove", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", \
    RUN+="/bin/systemctl stop orion-usb-mount@%k.service"
EOF

# ── 7. RetroArch installation ─────────────────────────────────────────────────
# Debian Bookworm minimal does NOT have RetroArch in the default repo.
# We download the arm64 nightly binary from libretro.
log "Installing RetroArch from libretro nightly..."

RA_URL="https://buildbot.libretro.com/nightly/linux/aarch64/RetroArch.7z"
RA_DEST="/usr/local/bin/retroarch"
RA_ASSETS="/usr/share/retroarch"

if command -v wget &>/dev/null; then
    mkdir -p /tmp/ra-install
    if wget -q --timeout=120 -O /tmp/ra-install/RetroArch.7z "$RA_URL" 2>/dev/null; then
        apt_install p7zip-full
        7z x /tmp/ra-install/RetroArch.7z -o/tmp/ra-install/ -y >/dev/null 2>&1 || true
        # Find the retroarch binary
        RA_BIN=$(find /tmp/ra-install -name "retroarch" -type f | head -1)
        if [[ -n "$RA_BIN" ]]; then
            install -m 755 "$RA_BIN" "$RA_DEST"
            # Copy assets if present
            RA_DATA=$(find /tmp/ra-install -name "retroarch" -type d | head -1)
            [[ -n "$RA_DATA" ]] && cp -r "$RA_DATA" "$RA_ASSETS" || true
            log "RetroArch installed: $($RA_DEST --version 2>&1 | head -1)"
        else
            warn "RetroArch binary not found in archive, trying apt fallback..."
            apt_install retroarch || warn "RetroArch not available via apt either"
        fi
        rm -rf /tmp/ra-install
    else
        warn "RetroArch download failed (no network?), trying apt..."
        apt_install retroarch || warn "RetroArch not available"
    fi
fi

# ── 8. libretro cores ─────────────────────────────────────────────────────────
log "Downloading libretro cores..."
CORES_URL="https://buildbot.libretro.com/nightly/linux/aarch64/latest/"
CORES_DEST="/usr/lib/libretro"
mkdir -p "$CORES_DEST"

CORES=(
    "nestopia_libretro"       # NES
    "snes9x_libretro"         # SNES
    "genesis_plus_gx_libretro" # Mega Drive
    "pcsx_rearmed_libretro"   # PlayStation
    "mgba_libretro"           # GBA
    "melonds_libretro"        # NDS
    "mednafen_pce_libretro"   # PC Engine
    "mednafen_wswan_libretro" # WonderSwan
)

for core in "${CORES[@]}"; do
    core_url="${CORES_URL}${core}.so.zip"
    if wget -q --timeout=60 -O "/tmp/${core}.zip" "$core_url" 2>/dev/null; then
        unzip -o -q "/tmp/${core}.zip" -d "$CORES_DEST" 2>/dev/null || true
        rm -f "/tmp/${core}.zip"
        log "Core installed: ${core}"
    else
        warn "Core download failed: ${core}"
    fi
done

# ── 9. EmulationStation ────────────────────────────────────────────────────────
log "Installing EmulationStation..."
# Try apt first (works on some Armbian releases), then GitHub release
if ! apt_install emulationstation emulationstation-de 2>/dev/null; then
    # Fallback: build from source or use pre-built binary
    # For now, create a placeholder that can be replaced
    warn "EmulationStation not found in apt — will need manual install or custom package"
fi

# ES configuration
mkdir -p /etc/emulationstation /home/${ORION_USER}/.emulationstation

cat > /etc/emulationstation/es_systems.xml << 'ESXML'
<?xml version="1.0" encoding="UTF-8"?>
<systemList>
  <system>
    <name>nes</name><fullname>Nintendo Entertainment System</fullname>
    <path>/roms/nes</path>
    <extension>.nes .NES .zip .ZIP .7z</extension>
    <command>retroarch -L /usr/lib/libretro/nestopia_libretro.so %ROM%</command>
    <platform>nes</platform><theme>nes</theme>
  </system>
  <system>
    <name>snes</name><fullname>Super Nintendo</fullname>
    <path>/roms/snes</path>
    <extension>.smc .sfc .SMC .SFC .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/libretro/snes9x_libretro.so %ROM%</command>
    <platform>snes</platform><theme>snes</theme>
  </system>
  <system>
    <name>megadrive</name><fullname>Sega Mega Drive</fullname>
    <path>/roms/megadrive</path>
    <extension>.md .gen .bin .MD .GEN .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/libretro/genesis_plus_gx_libretro.so %ROM%</command>
    <platform>megadrive</platform><theme>megadrive</theme>
  </system>
  <system>
    <name>psx</name><fullname>Sony PlayStation</fullname>
    <path>/roms/psx</path>
    <extension>.bin .cue .img .iso .pbp .chd</extension>
    <command>retroarch -L /usr/lib/libretro/pcsx_rearmed_libretro.so %ROM%</command>
    <platform>psx</platform><theme>psx</theme>
  </system>
  <system>
    <name>gba</name><fullname>Game Boy Advance</fullname>
    <path>/roms/gba</path>
    <extension>.gba .GBA .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/libretro/mgba_libretro.so %ROM%</command>
    <platform>gba</platform><theme>gba</theme>
  </system>
  <system>
    <name>nds</name><fullname>Nintendo DS</fullname>
    <path>/roms/nds</path>
    <extension>.nds .NDS .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/libretro/melonds_libretro.so %ROM%</command>
    <platform>nds</platform><theme>nds</theme>
  </system>
  <system>
    <name>pce</name><fullname>PC Engine</fullname>
    <path>/roms/pce</path>
    <extension>.pce .PCE .zip .ZIP</extension>
    <command>retroarch -L /usr/lib/libretro/mednafen_pce_libretro.so %ROM%</command>
    <platform>pcengine</platform><theme>pcengine</theme>
  </system>
  <system>
    <name>ports</name><fullname>Ports</fullname>
    <path>/roms/ports</path>
    <extension>.sh .SH</extension>
    <command>bash %ROM%</command>
    <platform>ports</platform><theme>ports</theme>
  </system>
</systemList>
ESXML

# ── 10. RetroArch global config ───────────────────────────────────────────────
log "Writing RetroArch config..."
mkdir -p /etc/retroarch /etc/retroarch/config

cat > /etc/retroarch/retroarch.cfg << 'RACFG'
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
savefile_directory = "/roms/saves"
savestate_directory = "/roms/states"
screenshot_directory = "/roms/screenshots"
menu_driver = "ozone"
rewind_enable = "false"
RACFG

# Per-system configs
echo 'rewind_enable = "true"'  > /etc/retroarch/config/Nestopia.cfg
echo 'rewind_enable = "true"'  > /etc/retroarch/config/Snes9x.cfg
echo 'rewind_enable = "true"'  > "/etc/retroarch/config/Genesis Plus GX.cfg"
printf 'rewind_enable = "false"\nvideo_scale_integer = "false"\n' > /etc/retroarch/config/PCSX-ReARMed.cfg
echo 'rewind_enable = "true"'  > /etc/retroarch/config/mGBA.cfg

# ── 11. PortMaster ────────────────────────────────────────────────────────────
log "Installing PortMaster stubs..."
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
        except Exception: pass
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
            ui.write(e.EV_KEY, BUTTON_MAP[ev.code], ev.value); ui.syn()

asyncio.run(main())
OGA
chmod +x /usr/lib/orion/oga-events.py

# ── 12. systemd services ───────────────────────────────────────────────────────
log "Installing systemd services..."

# EmulationStation autostart
cat > /etc/systemd/system/emulationstation.service << EOF
[Unit]
Description=EmulationStation
After=multi-user.target sound.target

[Service]
User=${ORION_USER}
Environment=HOME=/home/${ORION_USER}
ExecStart=/usr/bin/emulationstation
Restart=always
RestartSec=3
TTYPath=/dev/tty1
StandardInput=tty

[Install]
WantedBy=multi-user.target
EOF

# oga_events
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

# USB mount template
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

# Bluetooth gamepad
cat > /etc/systemd/system/orion-bluetooth.service << 'EOF'
[Unit]
Description=OrionOS BT Gamepad Auto-Pairing
After=bluetooth.service
Requires=bluetooth.service

[Service]
ExecStart=/usr/lib/orion/bt-gamepad.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# USB mount script
cat > /usr/lib/orion/mount-usb.sh << 'MOUNT'
#!/usr/bin/env bash
set -euo pipefail
DEV="${1:?}"; ACTION="${2:-add}"
MOUNT_BASE="/roms2"; MOUNT_PT="${MOUNT_BASE}/${DEV}"; DEVPATH="/dev/${DEV}"
ORION_USER="orion"

if [[ "$ACTION" == "remove" ]]; then
    umount -l "$MOUNT_PT" 2>/dev/null || true; rmdir "$MOUNT_PT" 2>/dev/null || true; exit 0
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

# Symlink rom subdirs
[[ -d "${MOUNT_PT}/roms" ]] && for d in "${MOUNT_PT}/roms"/*/; do
    sys="$(basename "$d")"
    [[ ! -e "/roms/${sys}" ]] && ln -sfn "$d" "/roms/${sys}" || true
done
logger -t orion-usb "Mounted ${DEV} (${FSTYPE}) at ${MOUNT_PT}"
MOUNT
chmod +x /usr/lib/orion/mount-usb.sh

# BT gamepad script
cat > /usr/lib/orion/bt-gamepad.sh << 'BT'
#!/usr/bin/env bash
set -euo pipefail
KNOWN="/var/lib/orion/bt-known"; mkdir -p /var/lib/orion; touch "$KNOWN"

bluetoothctl power on 2>/dev/null || true
bluetoothctl agent NoInputNoOutput 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true
bluetoothctl pairable on 2>/dev/null || true

# Reconnect known devices on startup
while IFS=' ' read -r mac _rest; do
    [[ -n "$mac" ]] && bluetoothctl connect "$mac" 2>/dev/null || true
done < "$KNOWN"

# Continuous scan loop
while true; do
    bluetoothctl scan on & SCAN=$!; sleep 30; kill $SCAN 2>/dev/null || true
    bluetoothctl scan off 2>/dev/null || true
    while IFS= read -r line; do
        mac=$(echo "$line" | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}' || true)
        [[ -z "$mac" ]] || grep -qiF "$mac" "$KNOWN" && continue
        cls=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Class:/{print $2}' || echo "")
        [[ -z "$cls" ]] && continue
        cls_int=$(( 16#${cls//0x/} ))
        (( (cls_int & 0x1F00) == 0x0500 )) || continue
        name=$(bluetoothctl info "$mac" 2>/dev/null | awk '/Name:/{$1="";print}' | xargs || echo "Gamepad")
        bluetoothctl pair "$mac" 2>/dev/null && bluetoothctl trust "$mac" 2>/dev/null \
            && bluetoothctl connect "$mac" 2>/dev/null && echo "$mac $name" >> "$KNOWN" \
            && logger -t orion-bt "Paired: $name ($mac)"
    done < <(bluetoothctl devices 2>/dev/null || true)
    sleep 10
done
BT
chmod +x /usr/lib/orion/bt-gamepad.sh

# ── 13. Enable services ────────────────────────────────────────────────────────
log "Enabling services..."
systemctl enable emulationstation.service 2>/dev/null || true
systemctl enable oga-events.service        2>/dev/null || true
systemctl enable orion-bluetooth.service   2>/dev/null || true
systemctl enable bluetooth.service         2>/dev/null || true
systemctl enable NetworkManager.service    2>/dev/null || true
systemctl disable getty@tty1.service       2>/dev/null || true

# ── 14. Ports menu shortcuts ───────────────────────────────────────────────────
log "Creating Ports shortcuts..."
mkdir -p /roms/ports

cat > "/roms/ports/WiFi Setup.sh"    <<'P'; chmod +x "/roms/ports/WiFi Setup.sh"
#!/usr/bin/env bash
nmtui-connect
P

cat > "/roms/ports/System Info.sh"   <<'P'; chmod +x "/roms/ports/System Info.sh"
#!/usr/bin/env bash
source /etc/orion/release 2>/dev/null || true
TEMP=$(cat /run/orion/cpu_temp 2>/dev/null || echo "?")
echo "OrionOS ${ORION_VERSION:-?} | CPU: ${TEMP}°C | $(uptime -p)"
echo "ROM: $(df -h /roms | awk 'NR==2{print $3"/"$2}')"
read -rp "Press Enter..."
P

cat > "/roms/ports/Check for Updates.sh" <<'P'; chmod +x "/roms/ports/Check for Updates.sh"
#!/usr/bin/env bash
echo "Checking for OrionOS updates..."
LATEST=$(curl -sf --max-time 10 \
    "https://api.github.com/repos/onex01/OrionOS/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4 || echo "?")
echo "Latest: ${LATEST}. Visit github.com/onex01/OrionOS/releases"
read -rp "Press Enter..."
P

chown -R "${ORION_USER}:${ORION_USER}" /roms

# ── 15. Runtime tmpdir ────────────────────────────────────────────────────────
cat > /etc/tmpfiles.d/orion.conf <<'EOF'
d /run/orion 0755 root root -
EOF

# ── 16. Release metadata ──────────────────────────────────────────────────────
cat > /etc/orion/release << EOF
ORION_VERSION="${ORION_VERSION}"
ORION_BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORION_BOARD="${BOARD:-orangepizero3}"
EOF

# ── Cleanup ───────────────────────────────────────────────────────────────────
log "Cleaning up..."
apt-get autoremove -y -qq 2>/dev/null || true
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* /tmp/ra-install /tmp/*.zip

log "=== OrionOS customize-image.sh DONE ==="
log "Build log: ${LOG}"
