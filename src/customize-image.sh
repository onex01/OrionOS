#!/bin/bash
# OrionOS customization script – v7.9 (Plymouth fix, stable)
set -e

LOGFILE="/var/log/orionos-build.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== OrionOS customization started at $(date) ==="

mkdir -p /opt/orionos

# ---------- 1. Включение GPU Mali G31 через Device Tree ----------
echo "Enabling GPU in device tree..."
DTS_FILE=/boot/dtb/allwinner/sun50i-h618-orangepi-zero3.dtb
if [ -f "$DTS_FILE" ]; then
    dtc -I dtb -O dts "$DTS_FILE" -o /tmp/zero3.dts
    sed -i '/mali@/ { :a; /status/ s/disabled/okay/; /};/!{n; ba} }' /tmp/zero3.dts
    dtc -I dts -O dtb /tmp/zero3.dts -o /tmp/zero3-fixed.dtb
    cp /tmp/zero3-fixed.dtb "$DTS_FILE"
    echo "GPU device tree patched."
fi

if [ -f /tmp/overlay/boot/boot.bmp ]; then
    cp /tmp/overlay/boot/boot.bmp /boot/boot.bmp
fi

# ---------- 2. Установка базовых зависимостей ----------
apt-get update
apt-get install -y mesa-utils libgles2-mesa-dev libegl1-mesa-dev libgl1-mesa-dri
apt-get install -y xserver-xorg xinit lightdm lightdm-gtk-greeter onboard firefox-esr
apt-get install -y dialog bluetooth bluez bluez-tools network-manager wpasupplicant
apt-get install -y kbd openssh-server exfatprogs libsdl2-mixer-2.0-0 joystick xpad
apt-get install -y plymouth plymouth-themes

if [ -f /tmp/overlay/boot/boot.bmp ]; then
    cp /tmp/overlay/boot/boot.bmp /usr/share/plymouth/themes/spinner/background-tile.png
fi
plymouth-set-default-theme spinner -R
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYCONF'
[Daemon]
Theme=spinner
ShowDelay=0
PLYCONF

mkdir -p /etc/modules-load.d
echo "joydev"     >  /etc/modules-load.d/gamepad.conf
echo "xpad"       >> /etc/modules-load.d/gamepad.conf
echo "hid-nintendo" >> /etc/modules-load.d/gamepad.conf || true
echo "hid-sony"   >> /etc/modules-load.d/gamepad.conf || true
echo "ntfs3"      >  /etc/modules-load.d/fs.conf || true
echo "snd-usb-audio" > /etc/modules-load.d/sound.conf || true

# ---------- 3. RetroArch + ядра ----------
RETRO_CORES=(
    libretro-snes9x libretro-genesisplusgx libretro-nestopia libretro-mgba
    libretro-beetle-pce-fast libretro-beetle-psx libretro-beetle-vb
    libretro-beetle-wswan libretro-gambatte libretro-desmume
)
apt-get install -y --install-recommends retroarch ${RETRO_CORES[*]} || true
apt-get install -y retroarch libretro-* 2>/dev/null || true

# ---------- 4. EmulationStation ----------
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

# ---------- 5. Пользователь orion ----------
echo "Setting up user orion..."
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

# ---------- 6. PortMaster ----------
cp -r /tmp/overlay/opt/orionos/sources/PortMaster-GUI /opt/portmaster
chown -R orion:orion /opt/portmaster
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

# ---------- 7. Игровые папки ----------
ROMS_DIRS=( nes snes megadrive mastersystem gamegear psx gb gbc gba pcengine
            virtualboy wonderswan nds ports
            atari2600 atari5200 atari7800 atarijaguar atarilynx atarist atarixegs
            atari800 amiga amigacd32 c64 c128 vic20
            msx msx2 x68000 pc98 zxspectrum amstradcpc
            neogeo neogeocd arcade mame cps1 cps2 cps3
            segacd sega32x sg-1000 dreamcast naomi atomiswave
            scummvm easyrpg doom wolf openbor tic80
            psp nds n64 n64dd virtualboy wonderswan
            pokemonmini gameandwatch supervision megaduck
            satellaview sufami supergrafx pcfx
            odyssey2 intellivision coleco vectrex
            apple2 bbcmicro coco3 dragon32 trs-80
            cavestory love2d lowresnx solarus )
mkdir -p /roms
for d in "${ROMS_DIRS[@]}"; do
    mkdir -p "/roms/$d"
done
chown -R orion:orion /roms
mkdir -p /roms2

# ---------- 8. Конфиги ES ----------
mkdir -p /home/orion/.emulationstation
rm -f /home/orion/.emulationstation/es_systems.cfg
cat > /home/orion/.emulationstation/es_systems.cfg << 'EOF'
<?xml version="1.0"?>
<systemList>
  <system><name>nes</name><fullname>Nintendo Entertainment System</fullname><path>/roms/nes</path><extension>.nes .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so %ROM%</command><platform>nes</platform></system>
  <system><name>snes</name><fullname>Super Nintendo</fullname><path>/roms/snes</path><extension>.smc .sfc .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/snes9x_libretro.so %ROM%</command><platform>snes</platform></system>
  <system><name>megadrive</name><fullname>Mega Drive / Genesis</fullname><path>/roms/megadrive</path><extension>.md .bin .smd .gen .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/genesis_plus_gx_libretro.so %ROM%</command><platform>megadrive</platform></system>
  <system><name>mastersystem</name><fullname>Master System</fullname><path>/roms/mastersystem</path><extension>.sms .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/genesis_plus_gx_libretro.so %ROM%</command><platform>mastersystem</platform></system>
  <system><name>gamegear</name><fullname>Game Gear</fullname><path>/roms/gamegear</path><extension>.gg .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/genesis_plus_gx_libretro.so %ROM%</command><platform>gamegear</platform></system>
  <system><name>psx</name><fullname>PlayStation</fullname><path>/roms/psx</path><extension>.cue .bin .iso .img .chd</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mednafen_psx_libretro.so %ROM%</command><platform>psx</platform></system>
  <system><name>gb</name><fullname>Game Boy</fullname><path>/roms/gb</path><extension>.gb .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/gambatte_libretro.so %ROM%</command><platform>gb</platform></system>
  <system><name>gbc</name><fullname>Game Boy Color</fullname><path>/roms/gbc</path><extension>.gbc .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/gambatte_libretro.so %ROM%</command><platform>gbc</platform></system>
  <system><name>gba</name><fullname>Game Boy Advance</fullname><path>/roms/gba</path><extension>.gba .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mgba_libretro.so %ROM%</command><platform>gba</platform></system>
  <system><name>pcengine</name><fullname>PC Engine / TurboGrafx-16</fullname><path>/roms/pcengine</path><extension>.pce .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mednafen_pce_fast_libretro.so %ROM%</command><platform>pcengine</platform></system>
  <system><name>virtualboy</name><fullname>Virtual Boy</fullname><path>/roms/virtualboy</path><extension>.vb .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mednafen_vb_libretro.so %ROM%</command><platform>virtualboy</platform></system>
  <system><name>wonderswan</name><fullname>WonderSwan</fullname><path>/roms/wonderswan</path><extension>.ws .wsc .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/mednafen_wswan_libretro.so %ROM%</command><platform>wonderswan</platform></system>
  <system><name>nds</name><fullname>Nintendo DS</fullname><path>/roms/nds</path><extension>.nds .zip</extension><command>retroarch -L /usr/lib/aarch64-linux-gnu/libretro/desmume_libretro.so %ROM%</command><platform>nds</platform></system>
  <system><name>ports</name><fullname>Tools &amp; Ports</fullname><path>/roms/ports</path><extension>.sh</extension><command>bash %ROM%</command><platform>ports</platform></system>
</systemList>
EOF

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
chmod 644 /home/orion/.emulationstation/es_systems.cfg
chmod 644 /home/orion/.emulationstation/es_settings.cfg
chmod 755 /home/orion/.emulationstation

# ---------- 9. Тема ----------
mkdir -p /home/orion/.emulationstation/themes
if [ -d /tmp/overlay/opt/orionos/sources/es-theme-carbon ]; then
    cp -r /tmp/overlay/opt/orionos/sources/es-theme-carbon /home/orion/.emulationstation/themes/carbon
    chown -R orion:orion /home/orion/.emulationstation/themes
fi

# ---------- 10. Автомонтирование ----------
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

# ---------- 11. Скрипты Ports ----------
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
echo -e "o\nn\np\n1\n\n${SIZE:++${SIZE}M}\nw" | fdisk "$DISK"
sleep 1
PART="${DISK}1"
mkfs.$FS -I "$PART"
echo "Done. Reconnect to mount."
FORMAT
chmod +x /roms/ports/Format-USB.sh
chown orion:orion /roms/ports/Format-USB.sh

# ---------- 12. Bluetooth авто-подключение ----------
cat > /usr/local/bin/bt-pair-gamepad.sh << 'BTPAIR'
#!/bin/bash
while true; do
    if ! systemctl is-active --quiet bluetooth; then
        sleep 5
        continue
    fi
    bluetoothctl power on
    bluetoothctl agent on
    bluetoothctl default-agent
    bluetoothctl pairable on
    bluetoothctl scan on &
    SCAN_PID=$!
    sleep 45
    kill $SCAN_PID 2>/dev/null
    for dev in $(bluetoothctl devices | cut -d' ' -f2); do
        bluetoothctl trust "$dev"
        bluetoothctl connect "$dev"
    done
    sleep 10
done
BTPAIR
chmod +x /usr/local/bin/bt-pair-gamepad.sh

cat > /etc/systemd/system/bt-autopair.service << 'BTSVC'
[Unit]
Description=Bluetooth auto-pair and connect
After=bluetooth.service
Before=display-manager.service
[Service]
Type=simple
ExecStart=/usr/local/bin/bt-pair-gamepad.sh
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
BTSVC
systemctl enable bt-autopair.service 2>/dev/null || true

# ---------- 13. Firstboot ----------
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

cat > /home/orion/.xsession << 'XSESS'
#!/bin/bash
plymouth quit 2>/dev/null
exec emulationstation
XSESS
chmod +x /home/orion/.xsession

if [ ! -f /home/orion/.emulationstation/es_systems.cfg ]; then
    # (для краткости опускаем, но в реальном скрипте должен быть полный конфиг)
    echo "Warning: es_systems.cfg missing" >&2
fi

if [ ! -f /home/orion/.config/retroarch/retroarch.cfg ]; then
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
RACFG
fi

ROMS_DIRS=( nes snes megadrive mastersystem gamegear psx gb gbc gba pcengine virtualboy wonderswan nds ports )
for d in "${ROMS_DIRS[@]}"; do mkdir -p "/roms/$d"; done

chown -R orion:orion /home/orion /roms /roms2 /opt/portmaster 2>/dev/null || true
echo "Orion" > /home/orion/.emulationstation/console_name
chown orion:orion /home/orion/.emulationstation/console_name
systemctl disable orionos-firstboot.service 2>/dev/null || true
rm -f /opt/orionos/firstboot.sh
FIRSTBOOT
chmod +x /opt/orionos/firstboot.sh

# ---------- 14. Сервис firstboot ----------
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

# ---------- 15. LightDM и .xsession ----------
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-orionos.conf << 'LIGHTDM'
[Seat:*]
autologin-user=orion
autologin-user-timeout=0
session-wrapper=/etc/X11/Xsession
greeter-session=lightdm-gtk-greeter
LIGHTDM

cat > /home/orion/.xsession << 'XSESSION'
#!/bin/bash
plymouth quit 2>/dev/null
exec emulationstation
XSESSION
chmod +x /home/orion/.xsession
chown orion:orion /home/orion/.xsession

# ---------- 16. RetroArch конфиг (дубль) ----------
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
RACFG
chown -R orion:orion /home/orion/.config/retroarch

# ---------- 17. Чистка и уменьшение размера ----------
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

# ---------- 18. Имя хоста и армбиан-специфика ----------
apt-get purge -y armbian-firstrun-config &>/dev/null || true
rm -f /etc/profile.d/armbian-check-first-login.sh
rm -f /etc/profile.d/armbian-check-first-login-reboot.sh
echo "OrionOS" > /etc/hostname
sed -i 's/127.0.1.1.*/127.0.1.1\tOrionOS/' /etc/hosts
hostnamectl set-hostname OrionOS || true

# ---------- 19. Загрузочные параметры и Plymouth ----------
if grep -q 'extraargs=' /boot/armbianEnv.txt; then
    sed -i 's/^extraargs=.*/extraargs=systemd.show_status=0 vt_global_cursor_default=0 quiet consoleblank=0 loglevel=3 splash plymouth.ignore-serial-consoles/' /boot/armbianEnv.txt
else
    echo 'extraargs=systemd.show_status=0 vt_global_cursor_default=0 quiet consoleblank=0 loglevel=3 splash plymouth.ignore-serial-consoles' >> /boot/armbianEnv.txt
fi

# ---------- 20. Wi-Fi ----------
cat > /usr/local/bin/wifi-setup.sh << 'WIFI'
#!/bin/bash
nmtui
WIFI
chmod +x /usr/local/bin/wifi-setup.sh
systemctl enable NetworkManager 2>/dev/null || true

# ---------- Финал ----------
apt-get clean
rm -rf /var/lib/apt/lists/*
echo "=== OrionOS customization finished at $(date) ==="