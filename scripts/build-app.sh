#!/bin/zsh
# Compila en modo release y empaqueta build/TCGPartner.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/TCGPartner.app
swift build -c release

# El icono se regenera si falta o si cambió la imagen fuente o el script que lo dibuja.
SRC=Resources/AppIconSource.png
if [[ ! -f Resources/AppIcon.icns || scripts/make-icon.swift -nt Resources/AppIcon.icns || ( -f $SRC && $SRC -nt Resources/AppIcon.icns ) ]]; then
  if [[ -f $SRC ]]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns $SRC
  else
    swift scripts/make-icon.swift Resources/AppIcon.icns
  fi
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/TCGPartner" "$APP/Contents/MacOS/TCGPartner"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Con una localización en español, macOS muestra en español los menús estándar (Archivo, Ventana…).
mkdir -p "$APP/Contents/Resources/es.lproj"
printf '"CFBundleName" = "TCG - Partner";\n' > "$APP/Contents/Resources/es.lproj/InfoPlist.strings"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TCG - Partner</string>
  <key>CFBundleDisplayName</key><string>TCG - Partner</string>
  <key>CFBundleIdentifier</key><string>dev.matt.TCGPartner</string>
  <key>CFBundleExecutable</key><string>TCGPartner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleLocalizations</key><array><string>es</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.card-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✅ $APP listo. Ábrelo con: open $APP"
