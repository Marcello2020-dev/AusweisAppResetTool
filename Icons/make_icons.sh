#!/bin/bash
set -euo pipefail

ICONS_DIR="/Users/Marcel/Git/github.com/Marcello2020-dev/AusweisAppResetTool/Icons"
SRC="$ICONS_DIR/AusweisAppResetTool_AppIcon_1024_color.png"

ICONSET="$ICONS_DIR/AusweisAppResetTool.iconset"
ICNS_OUT="$ICONS_DIR/AusweisAppResetTool.icns"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: Quelle nicht gefunden: $SRC"
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

gen() {
  local size="$1"
  local name="$2"
  /usr/bin/sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
}

gen 16   "icon_16x16.png"
gen 32   "icon_16x16@2x.png"

gen 32   "icon_32x32.png"
gen 64   "icon_32x32@2x.png"

gen 128  "icon_128x128.png"
gen 256  "icon_128x128@2x.png"

gen 256  "icon_256x256.png"
gen 512  "icon_256x256@2x.png"

gen 512  "icon_512x512.png"
cp -f "$SRC" "$ICONSET/icon_512x512@2x.png"

echo "OK: iconset erstellt: $ICONSET"

# .icns erzeugen
/usr/bin/iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
echo "OK: icns erstellt: $ICNS_OUT"

echo "Fertig."
