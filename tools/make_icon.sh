#!/usr/bin/env bash
# Renderiza el icono y lo empaqueta como .icns.
set -euo pipefail
cd "$(dirname "$0")/.."

swift tools/make_icon.swift

ICONSET="assets/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double assets/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
rm -rf "$ICONSET" assets/icon-1024.png
echo "escrito assets/AppIcon.icns"
