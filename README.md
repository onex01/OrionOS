# OrionOS

An autonomous gaming console OS based on Armbian for Orange Pi Zero3 (Allwinner H618).

## Features

- EmulationStation with hardware acceleration (Mali G31 / Panfrost)
- RetroArch cores: NES, SNES, Mega Drive, PlayStation, GBA, NDS, PC Engine, WonderSwan, Virtual Boy
- PortMaster GUI (fake `oga_events` service included)
- Bluetooth auto‑pairing of gamepads (service included)
- Automatic USB storage mounting into `/roms`
- Plymouth splash screen with custom logo
- Tools & Ports scripts: browser, Wi‑Fi setup, desktop (optional), USB format utility
- Supports wired gamepads, including Nintendo Pro Controller (via `hid-nintendo` module)

## Building

1. Clone the Armbian build repository and this OrionOS overlay repository.
2. Place `customize-image.sh` and the `overlay` directory into the Armbian `userpatches/` folder.
3. Run the build:
```bash
./compile.sh BOARD=orangepizero3 BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes \
    KERNEL_CONFIGURE=no EXTRA_ROOTFS_MIB_SIZE=800 FORCE_USE_RAMDISK=no \
    CUSTOMIZE_SCRIPT="userpatches/customize-image.sh"
```
4. The resulting image will be in `output/images/`.

**Optional:** If you want to enable extra kernel modules (hid‑nintendo, hid‑sony, ntfs3), set `KERNEL_CONFIGURE=yes` and select them in menuconfig. A preconfigured kernel config can be placed in `config/kernel/linux-sunxi64-current.config`.

## Installation

Write the image to a microSD card (8 GB minimum) using `dd` or Balena Etcher.  
After booting, EmulationStation will start automatically. The default user is `orion` with password `orion`.

## Adding ROMs

- Internal storage: `/roms/<system>` (e.g., `/roms/nes`, `/roms/psx`)
- USB drives: automatically mounted under `/roms2/<device>` and symlinked into `/roms/`.

## Post‑installation

- Wi‑Fi: open `Ports → WiFi Setup` (uses `nmtui`)
- Browser: `Ports → Browser`
- Desktop mode: `Ports → Desktop` (requires setting a root password)
