#!/bin/bash
# OrionOS Core Pruner — оставляет только whitelist ядра (.so файлы)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CORES_DIR="${1:-$ROOT_DIR/src/overlay/opt/orionos/cores}"
WHITELIST_FILE="${2:-$ROOT_DIR/config/cores-whitelist.txt}"

if [ ! -f "$WHITELIST_FILE" ]; then
    echo "ERROR: Whitelist not found: $WHITELIST_FILE" >&2
    echo "Create it first: $ROOT_DIR/config/cores-whitelist.txt" >&2
    exit 1
fi

cd "$CORES_DIR" || exit 1

echo "Pruning cores in $(pwd)..."
echo "Whitelist: $WHITELIST_FILE"

KEEP=$(grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | tr '\n' ' ')

for f in *.so; do
    [ -f "$f" ] || continue
    if ! echo "$KEEP" | grep -qw "$f"; then
        echo "  [-] Removing $f"
        rm -f "$f"
    else
        echo "  [+] Keeping $f"
    fi
done

# Удаляем оставшиеся zip-архивы если есть
for f in *.zip; do
    [ -f "$f" ] || continue
    echo "  [-] Removing leftover $f"
    rm -f "$f"
done

echo ""
echo "Done. Kept $(ls *.so 2>/dev/null | wc -l) cores."
du -sh . | awk '{print "Total size: " $1}'
