#!/bin/bash
# Синхронизация ядер с christianhaitian/retroarch-cores (aarch64)
# Ядра лежат в .zip архивах: corename_libretro.so.zip
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

UPSTREAM="https://github.com/christianhaitian/retroarch-cores/raw/master/aarch64"
CORES_DIR="$ROOT_DIR/src/overlay/opt/orionos/cores"
WHITELIST="$ROOT_DIR/config/cores-whitelist.txt"

mkdir -p "$CORES_DIR"

if [ ! -f "$WHITELIST" ]; then
    echo "ERROR: $WHITELIST not found!" >&2
    exit 1
fi

cd "$CORES_DIR"

echo "Downloading cores from upstream (zip archives)..."
echo "Cores dir: $(pwd)"
echo "Whitelist: $WHITELIST"

while IFS= read -r core; do
    [[ "$core" =~ ^#.*$ ]] && continue
    [[ -z "$core" ]] && continue

    # Имя zip-архива: corename_libretro.so.zip
    ZIP_NAME="${core}.zip"

    if [ ! -f "$core" ]; then
        echo "  [GET] $ZIP_NAME -> $core"
        wget -q --show-progress "$UPSTREAM/$ZIP_NAME" -O "/tmp/$ZIP_NAME" && {
            unzip -o "/tmp/$ZIP_NAME" -d "$CORES_DIR" && rm -f "/tmp/$ZIP_NAME"
            echo "  [OK] $core extracted"
        } || {
            echo "  [FAIL] $ZIP_NAME not found upstream"
            rm -f "/tmp/$ZIP_NAME"
        }
    else
        echo "  [OK] $core exists"
    fi
done < "$WHITELIST"

cd - >/dev/null
echo ""
echo "Sync complete. $(ls "$CORES_DIR"/*.so 2>/dev/null | wc -l) cores in folder."
du -sh "$CORES_DIR" | awk '{print "Total size: " $1}'
