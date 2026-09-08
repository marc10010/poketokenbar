#!/usr/bin/env bash
# Empaqueta el ejecutable SPM como .app de barra de menú (LSUIElement) y lo
# firma ad-hoc, que es lo mínimo que macOS pide para conservar permisos.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/PokeTokenBar.app"
BUNDLE_ID="dev.poketokenbar.app"
VERSION="0.1.0"

swift build -c release --product PokeTokenBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/PokeTokenBar" "$APP/Contents/MacOS/PokeTokenBar"

# El bundle de recursos que genera SPM lleva la Pokédex embebida.
for resource in .build/release/*.bundle; do
  [ -e "$resource" ] && cp -R "$resource" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PokeTokenBar</string>
  <key>CFBundleDisplayName</key><string>PokeTokenBar</string>
  <key>CFBundleExecutable</key><string>PokeTokenBar</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Sin icono en el Dock: la app vive solo en la barra de menú. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "aviso: no se pudo firmar ad-hoc; la app funciona igual en local"

echo "listo: $APP"
echo "instalar: cp -R $APP /Applications/"
