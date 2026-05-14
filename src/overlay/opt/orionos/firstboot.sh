#!/bin/bash
# OrionOS First Boot — v8.0
set -e

LOGFILE="/var/log/orionos-firstboot.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== OrionOS First Boot $(date) ==="

# --- 1. Модули ядра ---
modprobe joydev 2>/dev/null || true
modprobe xpad 2>/dev/null || true
modprobe hid-nintendo 2>/dev/null || true
modprobe hid-sony 2>/dev/null || true
modprobe snd-usb-audio 2>/dev/null || true

# --- 2. Пользователь ---
if ! id -u orion &>/dev/null; then
    useradd -m -d /home/orion -s /bin/bash \
        -G audio,video,input,dialout,netdev,bluetooth orion
    echo "orion:orion" | chpasswd
fi

# --- 3. Директории ---
mkdir -p /home/orion/.emulationstation
mkdir -p /home/orion/.config/retroarch/{savestates,saves,shaders,system}
mkdir -p /roms /roms2
mkdir -p /opt/orionos/configs /opt/orionos/tools

# --- 4. Конфиг EmulationStation ---
if [ -f /opt/orionos/configs/es_systems.cfg ]; then
    cp /opt/orionos/configs/es_systems.cfg /home/orion/.emulationstation/
    echo "[Firstboot] es_systems.cfg copied from overlay"
else
    echo "[Firstboot] WARNING: es_systems.cfg not found in overlay!"
fi

if [ -f /opt/orionos/configs/es_input.cfg ]; then
    cp /opt/orionos/configs/es_input.cfg /home/orion/.emulationstation/
    echo "[Firstboot] es_input.cfg copied from overlay"
fi

# --- 5. Конфиг RetroArch ---
if [ ! -f /home/orion/.config/retroarch/retroarch.cfg ]; then
    cat > /home/orion/.config/retroarch/retroarch.cfg << 'RACFG'
video_driver = "gl"
video_threaded = "true"
video_vsync = "false"
video_max_swapchain_images = "2"
video_scale_integer = "false"
video_smooth = "false"
video_force_aspect = "true"
video_aspect_ratio_auto = "true"
video_shader_enable = "false"
audio_driver = "alsa"
audio_enable = "true"
audio_out_rate = "48000"
input_driver = "udev"
input_joypad_driver = "udev"
menu_swap_ok_cancel_buttons = "false"
savestate_directory = "~/.config/retroarch/savestates"
savefile_directory = "~/.config/retroarch/saves"
cheat_database_path = "~/.config/retroarch/cheats"
system_directory = "~/.config/retroarch/system"
assets_directory = "/usr/share/libretro/assets"
RACFG
fi

# --- 6. Xsession (автозапуск ES) ---
cat > /home/orion/.xsession << 'XSESS'
#!/bin/bash
# Принудительно закрываем Plymouth перед запуском ES
if systemctl is-active --quiet plymouth-quit-wait; then
    sudo systemctl stop plymouth-quit-wait 2>/dev/null || true
fi
plymouth quit 2>/dev/null || true
exec emulationstation
XSESS
chmod +x /home/orion/.xsession

# --- 7. Игровые папки ---
ROMS_DIRS=(
  nes snes n64 gb gbc gba nds pokemini virtualboy gw
  megadrive mastersystem gamegear segacd sega32x sg-1000 dreamcast saturn segaarcade
  psx psp
  pcengine pcenginecd supergrafx
  arcade mame neogeo neogeocd cps1 cps2 cps3
  atari2600 atari5200 atari7800 atarilynx atari800 atarist
  c64 c128 vic20 amiga amigacd32
  dos msx msx2 zxspectrum amstradcpc
  odyssey2 intellivision colecovision vectrex
  wonderswan wonderswancolor ngp ngpc supervision
  3do cdi
  doom quake scummvm easyrpg cavestory wolf3d xrick cannonball
  pico8 tic80 lowresnx vircon32 wasm4
  ports
)
for d in "${ROMS_DIRS[@]}"; do
    mkdir -p "/roms/$d"
done

# --- 8. Расширение ФС ---
if [ -x /opt/orionos/tools/resize-fs.sh ]; then
    /opt/orionos/tools/resize-fs.sh || true
fi

# --- 9. Права ---
chown -R orion:orion /home/orion /roms /roms2 /opt/portmaster 2>/dev/null || true
echo "OrionOS" > /home/orion/.emulationstation/console_name
chown orion:orion /home/orion/.emulationstation/console_name 2>/dev/null || true

# --- 10. Отключаем себя ---
systemctl disable orionos-firstboot.service 2>/dev/null || true
rm -f /opt/orionos/firstboot.sh

echo "=== First Boot finished $(date) ==="
