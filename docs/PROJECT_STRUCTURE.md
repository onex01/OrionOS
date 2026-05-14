# ═══════════════════════════════════════════════════════════════
# OrionOS — Final Project Structure
# ═══════════════════════════════════════════════════════════════

OrionOS/
├── .gitignore                          ← Игнорирует ядра, темы, sources, armbian-build
├── .github/
│   └── workflows/
│       └── build.yml                   ← CI/CD (опционально)
├── config/
│   ├── cores-whitelist.txt             ← Белый список ядер (~48 штук)
│   └── kernel/
│       └── linux-sunxi64-current.config
├── docs/
│   └── BUILD.md                        ← Инструкция по сборке
├── packages/                           ← .deb пакеты (пусто, для будущего)
├── scripts/
│   ├── orionos.sh          ⭐          ← Главное TUI меню (wrapper)
│   ├── build.sh                       ← Сборка образа Armbian
│   ├── compress.sh                    ← Сжатие .img → .tar.xz
│   ├── clean.sh                       ← Очистка артефактов (спрашивает про armbian-build)
│   ├── distclean.sh                   ← Полная очистка ВСЕГО
│   ├── sync-cores.sh                  ← Скачивание ядер (.zip → .so)
│   ├── sync-themes.sh                 ← Скачивание 5 тем ES
│   ├── sync-resources.sh              ← EmulationStation + PortMaster
│   ├── prune-cores.sh                 ← Удаление лишних ядер
│   ├── diagnose-project.sh            ← Диагностика структуры
│   └── mkimage.sh                     ← Создание .img из rootfs
├── src/
│   ├── customize-image.sh             ← Главный скрипт кастомизации (v8.0)
│   └── overlay/                       ← Файловая система для копирования в образ
│       ├── boot/
│       │   └── boot.bmp
│       ├── etc/
│       │   ├── bluetooth/
│       │   │   └── main.conf
│       │   ├── lightdm/
│       │   │   └── lightdm.conf.d/
│       │   │       └── 50-orionos.conf
│       │   ├── modules-load.d/
│       │   ├── systemd/
│       │   │   └── system/
│       │   │       ├── bt-autopair.service
│       │   │       ├── oga_events.service
│       │   │       └── orionos-firstboot.service
│       │   ├── udev/
│       │   │   └── rules.d/
│       │   │       └── 99-external-storage.rules
│       │   └── X11/
│       ├── opt/
│       │   └── orionos/
│       │       ├── cores/             ← .so ядра (в .gitignore!)
│       │       ├── themes/            ← Темы ES (в .gitignore!)
│       │       ├── sources/           ← Git-репозитории (в .gitignore!)
│       │       │   ├── EmulationStation/
│       │       │   ├── PortMaster-GUI/
│       │       │   └── es-theme-carbon/
│       │       ├── configs/
│       │       │   ├── cores-whitelist.txt
│       │       │   ├── es_systems.cfg
│       │       │   └── es_input.cfg
│       │       └── tools/
│       │           ├── diagnostics.sh
│       │           ├── resize-fs.sh
│       │           ├── save-input.sh
│       │           └── launch-portmaster.sh
│       └── usr/
│           └── local/
│               └── bin/
│                   ├── automount.sh
│                   ├── bt-pair-gamepad.sh
│                   └── wifi-setup.sh
└── README.md

# ═══════════════════════════════════════════════════════════════
# Правила размещения:
# ═══════════════════════════════════════════════════════════════
#
# Что НЕ коммитим (скачивается скриптами):
#   • src/overlay/opt/orionos/cores/*.so        → sync-cores.sh
#   • src/overlay/opt/orionos/themes/*          → sync-themes.sh
#   • src/overlay/opt/orionos/sources/*         → sync-resources.sh
#   • armbian-build/                            → build.sh
#
# Что КОММИТИМ (наши файлы):
#   • config/                                   → whitelist, kernel config
#   • scripts/                                  → все .sh
#   • src/customize-image.sh                    → кастомизация
#   • src/overlay/ (кроме cores, themes, sources)
#   • docs/, packages/, .github/
#
# ═══════════════════════════════════════════════════════════════