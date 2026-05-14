#!/bin/bash
# OrionOS customization script – v8.0 (Whitelist cores, BT fix, PortMaster SDL2, Tools)
set -e

LOGFILE="/var/log/orionos-build.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== OrionOS customization v8.0 started at $(date) ==="

mkdir -p /opt/orionos/{configs,tools}

# ---------- 1. GPU Mali G31 через Device Tree ----------
echo "[1/19] Enabling GPU in device tree..."
DTS_FILE=/boot/dtb/allwinner/sun50i-h618-orangepi-zero3.dtb
if [ -f "$DTS_FILE" ]; then
    dtc -I dtb -O dts "$DTS_FILE" -o /tmp/zero3.dts 2>/dev/null || true
    if [ -f /tmp/zero3.dts ]; then
        sed -i '/mali@/ { :a; /status/ s/disabled/okay/; /};/!{n; ba} }' /tmp/zero3.dts
        dtc -I dts -O dtb /tmp/zero3.dts -o /tmp/zero3-fixed.dtb 2>/dev/null || true
        cp /tmp/zero3-fixed.dtb "$DTS_FILE" 2>/dev/null || true
        echo "GPU device tree patched."
    fi
fi

if [ -f /tmp/overlay/boot/boot.bmp ]; then
    cp /tmp/overlay/boot/boot.bmp /boot/boot.bmp 2>/dev/null || true
fi

# ---------- 2. Базовые зависимости ----------
echo "[2/19] Installing base dependencies..."
apt-get update

# Mesa / GPU
apt-get install -y mesa-utils libgles2-mesa-dev libegl1-mesa-dev libgl1-mesa-dri

# X11 / DM
apt-get install -y xserver-xorg xinit nodm

# Сеть / BT
apt-get install -y dialog bluetooth bluez bluez-tools network-manager wpasupplicant

# Игровые / SDL2 (полный стек для PortMaster)
apt-get install -y kbd openssh-server exfatprogs libsdl2-2.0-0 libsdl2-dev \
    libsdl2-image-2.0-0 libsdl2-mixer-2.0-0 libsdl2-ttf-2.0-0 libsdl2-gfx-1.0-0 \
    libsdl2-mixer-2.0-0 joystick xpad

# Python
apt-get install -y python3-pip python3-venv python3-sdl2

# Plymouth
apt-get install -y plymouth plymouth-themes

if [ -f /tmp/overlay/boot/boot.bmp ]; then
    cp /tmp/overlay/boot/boot.bmp /usr/share/plymouth/themes/spinner/background-tile.png 2>/dev/null || true
fi
plymouth-set-default-theme spinner -R

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYCONF'
[Daemon]
Theme=spinner
ShowDelay=0
PLYCONF

# ---------- 3. Модули ядра ----------
echo "[3/19] Installing core modules..."
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/gamepad.conf << 'MODCONF'
joydev
xpad
hid-nintendo
hid-sony
MODCONF

cat > /etc/modules-load.d/fs.conf << 'MODCONF'
ntfs3
MODCONF

cat > /etc/modules-load.d/sound.conf << 'MODCONF'
snd-usb-audio
MODCONF

# ---------- 4. RetroArch ----------
echo "[419] Installing RetroArch..."
apt-get install -y retroarch libretro-*

# ---------- 5. Whitelist ядра ----------
echo "[5/19] Installing whitelisted libretro cores..."
mkdir -p /usr/lib/aarch64-linux-gnu/libretro

if [ -d /tmp/overlay/opt/orionos/cores ]; then
    # Копируем только ядра из whitelist
    if [ -f /tmp/overlay/opt/orionos/configs/cores-whitelist.txt ]; then
        while IFS= read -r core; do
            [[ "$core" =~ ^#.*$ ]] && continue
            [[ -z "$core" ]] && continue
            if [ -f "/tmp/overlay/opt/orionos/cores/$core" ]; then
                cp "/tmp/overlay/opt/orionos/cores/$core" /usr/lib/aarch64-linux-gnu/libretro/
                echo "  [+] $core"
            else
                echo "  [-] $core missing in overlay"
            fi
        done < /tmp/overlay/opt/orionos/configs/cores-whitelist.txt
    else
        echo "WARNING: cores-whitelist.txt not found, copying all cores..."
        cp /tmp/overlay/opt/orionos/cores/*.so /usr/lib/aarch64-linux-gnu/libretro/ 2>/dev/null || true
    fi
    chmod 644 /usr/lib/aarch64-linux-gnu/libretro/*.so
fi

# Удаляем лишние ядра из пакета retroarch (не из whitelist)
if [ -f /tmp/overlay/opt/orionos/configs/cores-whitelist.txt ]; then
    echo "[5b] Pruning system cores not in whitelist..."
    WHITELIST=$(cat /tmp/overlay/opt/orionos/configs/cores-whitelist.txt | grep -v '^#' | grep -v '^$' | tr '\n' ' ')
    for f in /usr/lib/aarch64-linux-gnu/libretro/*.so; do
        [ -f "$f" ] || continue
        core=$(basename "$f")
        if ! echo "$WHITELIST" | grep -qw "$core"; then
            echo "  [rm] $core"
            rm -f "$f"
        fi
    done
fi

# ---------- 6. EmulationStation ----------
echo "[6/19] Building EmulationStation..."
apt-get install -y libsdl2-dev libboost-system-dev libboost-filesystem-dev \
    libboost-date-time-dev libboost-locale-dev libfreeimage-dev libfreetype6-dev \
    libeigen3-dev libcurl4-openssl-dev libasound2-dev libgl1-mesa-dev \
    build-essential cmake fonts-droid-fallback fonts-noto fonts-dejavu

cp -r /tmp/overlay/opt/orionos/sources/EmulationStation /tmp/EmulationStation
sed -i '1s/^/#include <stack>\n/' /tmp/EmulationStation/es-app/src/views/gamelist/ISimpleGameListView.h
sed -i '1s/^/#include <stack>\n/' /tmp/EmulationStation/es-app/src/views/gamelist/BasicGameListView.cpp
cd /tmp/EmulationStation
cmake . && make -j$(nproc) && make install
cd / && rm -rf /tmp/EmulationStation

# ---------- 7. Пользователь orion ----------
echo "[7/19] Setting up user orion..."
if id -u orion &>/dev/null; then
    userdel -r orion 2>/dev/null || true
    rm -rf /home/orion
fi
useradd -m -d /home/orion -s /bin/bash \
    -G audio,video,input,dialout,netdev,bluetooth orion
echo "orion:orion" | chpasswd
if [ ! -d /home/orion ]; then
    echo "ERROR: /home/orion does not exist after useradd!" >&2
    exit 1
fi
chown -R orion:orion /home/orion

# ---------- 8. PortMaster ----------
echo "[8/19] Setting up PortMaster..."
mkdir -p /roms/ports/PortMaster
cp -r /tmp/overlay/opt/orionos/sources/PortMaster-GUI/* /roms/ports/PortMaster/ 2>/dev/null || true
ln -sf /roms/ports/PortMaster /opt/portmaster 2>/dev/null || true
chown -R orion:orion /roms/ports/PortMaster /opt/portmaster 2>/dev/null || true

# Python SDL2 для PortMaster GUI
pip3 install --break-system-packages pysdl2 pysdl2-dll 2>/dev/null || \
    pip3 install pysdl2 pysdl2-dll 2>/dev/null || \
    pip3 install PySDL2 2>/dev/null || true

# Wrapper для запуска PortMaster
mkdir -p /opt/orionos/tools
cat > /opt/orionos/tools/launch-portmaster.sh << 'PMW'
#!/bin/bash
export SDL_VIDEODRIVER=x11
export DISPLAY=:0
cd /roms/ports/PortMaster || exit 1
./PortMaster.sh
PMW
chmod +x /opt/orionos/tools/launch-portmaster.sh

# Fake oga_events
cat > /etc/systemd/system/oga_events.service << 'OGA'
[Unit]
Description=Fake OGA events service
[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
OGA
systemctl enable oga_events.service 2>/dev/null || true

# ---------- 9. Игровые папки ----------
echo "[9/19] Creating ROM directories..."
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
mkdir -p /roms
for d in "${ROMS_DIRS[@]}"; do
    mkdir -p "/roms/$d"
done
chown -R orion:orion /roms
mkdir -p /roms2

# ---------- 10. Конфиги ES ----------
echo "[10/10] Installing ES configs..."
mkdir -p /home/orion/.emulationstation

# Копируем полный конфиг из overlay (если есть)
if [ -f /tmp/overlay/opt/orionos/configs/es_systems.cfg ]; then
    cp /tmp/overlay/opt/orionos/configs/es_systems.cfg /opt/orionos/configs/
    cp /tmp/overlay/opt/orionos/configs/es_systems.cfg /home/orion/.emulationstation/
fi
if [ -f /tmp/overlay/opt/orionos/configs/es_input.cfg ]; then
    cp /tmp/overlay/opt/orionos/configs/es_input.cfg /opt/orionos/configs/
    cp /tmp/overlay/opt/orionos/configs/es_input.cfg /home/orion/.emulationstation/
fi

cat > /home/orion/.emulationstation/es_settings.cfg << 'ESET'
<?xml version="1.0"?>
<bool name="ClockMode12" value="false" />
<bool name="DrawClock" value="false" />
<bool name="FavoritesFirst" value="false" />
<bool name="QuickSystemSelect" value="false" />
<bool name="ScrapeVideos" value="true" />
<bool name="ScreenSaverMarquee" value="false" />
<int name="MaxVRAM" value="150" />
<int name="gba.sort" value="3" />
<int name="nes.sort" value="0" />
<int name="snes.sort" value="0" />
<string name="CollectionSystemsAuto" value="all,favorites" />
<string name="FolderViewMode" value="always" />
<string name="HiddenSystems" value="" />
<string name="Language" value="ru" />
<string name="LogLevel" value="disabled" />
<string name="SaveGamelistsMode" value="on exit" />
<string name="ScrapperRegionSrc" value="EU" />
<string name="ScreenSaverBehavior" value="random video" />
<string name="ScreenSaverGameInfo" value="always" />
<string name="ThemeRegionName" value="" />
<string name="ThemeSet" value="carbon" />
<string name="TransitionStyle" value="slide" />
<string name="VerbalBatteryWarning" value="no" />
ESET

touch /home/orion/.emulationstation/es_input.cfg
chown -R orion:orion /home/orion/.emulationstation
chmod 644 /home/orion/.emulationstation/es_systems.cfg 2>/dev/null || true
chmod 644 /home/orion/.emulationstation/es_settings.cfg
chmod 755 /home/orion/.emulationstation

# ---------- 11. Тема ----------
echo "[11/19] Installing ES themes..."
mkdir -p /home/orion/.emulationstation/themes
if [ -d /tmp/overlay/opt/orionos/sources/es-theme-carbon ]; then
    cp -r /tmp/overlay/opt/orionos/sources/es-theme-carbon /home/orion/.emulationstation/themes/carbon
    chown -R orion:orion /home/orion/.emulationstation/themes
fi

# ---------- 12. Автомонтирование ----------
echo "[12/19] Installing automount script..."
cat > /etc/udev/rules.d/99-external-storage.rules << 'UDEV'
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", RUN+="/usr/local/bin/automount.sh %k"
UDEV

cat > /usr/local/bin/automount.sh << 'AUTOMOUNT'
#!/bin/bash
DEVNAME=$1
MNTPOINT="/roms2/${DEVNAME}"
mkdir -p "$MNTPOINT"
mount /dev/${DEVNAME} "$MNTPOINT" 2>/dev/null || { rmdir "$MNTPOINT"; exit 1; }
chown -R orion:orion "$MNTPOINT"
DIRS=( nes snes megadrive mastersystem gamegear psx gb gbc gba pcengine virtualboy wonderswan nds ports )
for d in "${DIRS[@]}"; do
    mkdir -p "$MNTPOINT/$d"
    chown orion:orion "$MNTPOINT/$d"
    [ ! -e "/roms/${DEVNAME}-$d" ] && ln -sf "$MNTPOINT/$d" "/roms/${DEVNAME}-$d"
done
AUTOMOUNT
chmod +x /usr/local/bin/automount.sh

# ---------- 13. Скрипты Ports ----------
echo "[13/19] Installing ports script..."
cat > /roms/ports/Browser.sh << 'BROWSER'
#!/bin/bash
onboard &
firefox-esr
BROWSER
chmod +x /roms/ports/Browser.sh
chown orion:orion /roms/ports/Browser.sh

cat > /roms/ports/WiFi_Setup.sh << 'WIFI'
#!/bin/bash
sudo nmtui
WIFI
chmod +x /roms/ports/WiFi_Setup.sh
chown orion:orion /roms/ports/WiFi_Setup.sh

cat > /roms/ports/Desktop.sh << 'DESKTOP'
#!/bin/bash
if ! sudo -n true 2>/dev/null; then
    dialog --msgbox "A root password is required. Please set one now." 6 50
    sudo passwd root
fi
pkill -f emulationstation
sleep 1
startxfce4
DESKTOP
chmod +x /roms/ports/Desktop.sh
chown orion:orion /roms/ports/Desktop.sh

cat > /roms/ports/Rescan_Bluetooth.sh << 'RESCAN'
#!/bin/bash
dialog --title "Bluetooth" --infobox "Restarting Bluetooth scan..." 5 40
sudo systemctl restart bt-autopair.service
sleep 2
dialog --title "Bluetooth" --msgbox "Bluetooth scan restarted.\\n\\nPut your controller in pairing mode (hold Sync button)." 10 50
RESCAN
chmod +x /roms/ports/Rescan_Bluetooth.sh
chown orion:orion /roms/ports/Rescan_Bluetooth.sh

cat > /roms/ports/Format-USB.sh << 'FORMAT'
#!/bin/bash
DEVS=$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | grep -v "mmcblk0" | awk '{print "/dev/"$1, $2}')
[ -z "$DEVS" ] && dialog --msgbox "No external disks found." 5 40 && exit 1
TMPFILE=$(mktemp)
dialog --title "Select Disk" --menu "Choose a disk:" 12 60 6 $DEVS 2> $TMPFILE
DISK=$(cat $TMPFILE); rm -f $TMPFILE
[ -z "$DISK" ] && exit 0
dialog --yesno "All data on $DISK will be lost! Continue?" 6 50 || exit 0
dialog --menu "Filesystem:" 10 40 2 exfat "exFAT" ext4 "ext4" 2> $TMPFILE
FS=$(cat $TMPFILE); rm -f $TMPFILE
[ -z "$FS" ] && exit 0
dialog --menu "Partition size:" 10 40 2 full "Entire disk" custom "Specify MB" 2> $TMPFILE
SIZEOPT=$(cat $TMPFILE); rm -f $TMPFILE
[ -z "$SIZEOPT" ] && exit 0
if [ "$SIZEOPT" = "custom" ]; then
    dialog --inputbox "Size in MB:" 8 40 2> $TMPFILE
    SIZE=$(cat $TMPFILE); rm -f $TMPFILE
    [ -z "$SIZE" ] && exit 0
fi
umount ${DISK}* 2>/dev/null || true
echo -e "o\\nn\\np\\n1\\n\\n${SIZE:++${SIZE}M}\\nw" | fdisk "$DISK"
sleep 1
PART="${DISK}1"
mkfs.$FS -I "$PART"
echo "Done. Reconnect to mount."
FORMAT
chmod +x /roms/ports/Format-USB.sh
chown orion:orion /roms/ports/Format-USB.sh

# ---------- 14. Bluetooth (улучшенный) ----------
echo "[14/19] Setting up Bluetooth..."

# BlueZ main.conf из overlay
if [ -f /tmp/overlay/etc/bluetooth/main.conf ]; then
    mkdir -p /etc/bluetooth
    cp /tmp/overlay/etc/bluetooth/main.conf /etc/bluetooth/main.conf
fi

# Скрипт автопейринга из overlay
if [ -f /tmp/overlay/usr/local/bin/bt-pair-gamepad.sh ]; then
    cp /tmp/overlay/usr/local/bin/bt-pair-gamepad.sh /usr/local/bin/bt-pair-gamepad.sh
else
    cat > /usr/local/bin/bt-pair-gamepad.sh << 'BTPAIR'
#!/bin/bash
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket

while ! bluetoothctl show &>/dev/null; do
    sleep 2
done

bluetoothctl power on
bluetoothctl agent NoInputNoOutput
bluetoothctl default-agent
bluetoothctl pairable on
bluetoothctl discoverable on

while true; do
    timeout 30 bluetoothctl scan on >/dev/null 2>&1
    sleep 2
    bluetoothctl devices Paired | while read -r _ MAC _; do
        [ -n "$MAC" ] && bluetoothctl connect "$MAC" 2>/dev/null
    done
    sleep 15
done
BTPAIR
fi
chmod +x /usr/local/bin/bt-pair-gamepad.sh

cat > /etc/systemd/system/bt-autopair.service << 'BTSVC'
[Unit]
Description=Bluetooth auto-pair and connect
After=bluetooth.service dbus.service
Wants=bluetooth.service
[Service]
Type=simple
User=root
Environment="DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket"
ExecStart=/usr/local/bin/bt-pair-gamepad.sh
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
BTSVC
systemctl enable bt-autopair.service 2>/dev/null || true
usermod -a -G bluetooth orion

# ---------- 15. Firstboot ----------
echo "[15/19] Installing firstboot script..."
if [ -f /tmp/overlay/opt/orionos/firstboot.sh ]; then
    cp /tmp/overlay/opt/orionos/firstboot.sh /opt/orionos/firstboot.sh
else
    cat > /opt/orionos/firstboot.sh << 'FIRSTBOOT'
#!/bin/bash
modprobe joydev 2>/dev/null || true
modprobe hid-nintendo 2>/dev/null || true
modprobe hid-sony 2>/dev/null || true

if ! id -u orion &>/dev/null; then
    useradd -m -d /home/orion -s /bin/bash -G audio,video,input,dialout,netdev,bluetooth orion
    echo "orion:orion" | chpasswd
fi
mkdir -p /home/orion/.emulationstation /home/orion/.config/retroarch /roms /roms2

if [ -f /home/orion/.xsession ]; then
    plymouth quit 2>/dev/null || true
    exec emulationstation
fi
chown -R orion:orion /home/orion /roms /roms2 /opt/portmaster 2>/dev/null || true
systemctl disable orionos-firstboot.service 2>/dev/null || true
rm -f /opt/orionos/firstboot.sh
FIRSTBOOT
fi
chmod +x /opt/orionos/firstboot.sh

cat > /etc/systemd/system/orionos-firstboot.service << 'SERVICE'
[Unit]
Description=OrionOS First Boot Setup
After=multi-user.target
Before=display-manager.service
ConditionPathExists=/opt/orionos/firstboot.sh
[Service]
Type=oneshot
ExecStart=/opt/orionos/firstboot.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable orionos-firstboot.service

# ---------- 16. RetroArch конфиг ----------
echo "[16/19] RetroArch config..."
mkdir -p /home/orion/.config/retroarch
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
chown -R orion:orion /home/orion/.config/retroarch

# ---------- 17. Инструменты OrionOS ----------
echo "[17/19] Installing OrionOS tools..."
if [ -d /tmp/overlay/opt/orionos/tools ]; then
    cp -r /tmp/overlay/opt/orionos/tools/* /opt/orionos/tools/ 2>/dev/null || true
fi
chmod +x /opt/orionos/tools/*.sh 2>/dev/null || true

# ---------- 18. Флаг resize + чистка ----------
echo "[18/19] Final cleanup..."
touch /opt/orionos/.resize-needed

# Маскируем armbian-firstrun полностью
systemctl mask armbian-firstrun.service 2>/dev/null || true
systemctl disable console-setup.service 2>/dev/null || true
apt-get purge -y --allow-remove-essential man-db manpages manpages-dev \
    debian-faq doc-debian info iptables ppp modemmanager 2>/dev/null || true
apt-get autoremove -y || true
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
rm -rf /usr/share/info/*
rm -rf /usr/share/locale/??_?? 2>/dev/null || true

# Удаляем firmware для ненужных GPU
rm -rf /lib/firmware/{amdgpu,i915,nvidia,radeon} 2>/dev/null || true

# Очистка кэшей
rm -rf /var/cache/* /tmp/* /var/tmp/*

# ---------- 19. Имя хоста и загрузка ----------
echo "[19/19] Finalizing..."
apt-get purge -y armbian-firstrun-config &>/dev/null || true
rm -f /etc/profile.d/armbian-check-first-login.sh
rm -f /etc/profile.d/armbian-check-first-login-reboot.sh
echo "OrionOS" > /etc/hostname
sed -i 's/127.0.1.1.*/127.0.1.1\tOrionOS/' /etc/hosts
hostnamectl set-hostname OrionOS || true

# extraargs
if grep -q 'extraargs=' /boot/armbianEnv.txt; then
    sed -i 's/^extraargs=.*/extraargs=systemd.show_status=0 vt_global_cursor_default=0 quiet consoleblank=0 loglevel=3 splash plymouth.ignore-serial-consoles/' /boot/armbianEnv.txt
else
    echo 'extraargs=systemd.show_status=0 vt_global_cursor_default=0 quiet consoleblank=0 loglevel=3 splash plymouth.ignore-serial-consoles' >> /boot/armbianEnv.txt
fi

# Wi-Fi
systemctl enable NetworkManager 2>/dev/null || true

# Финальная чистка
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== OrionOS v8.0 customization finished at $(date) ==="
