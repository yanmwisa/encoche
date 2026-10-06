#!/bin/bash
# Construit build/NotchDrop.app avec les seuls Command Line Tools (sans Xcode).
# Limites connues : textes en anglais (catalogues de traduction = Xcode).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="NotchDrop"
APP_DIR="build/${APP_NAME}.app"
BUNDLE_ID="io.github.yanmwisa.encoche"
APP_VERSION="2.16"
BUILD_NUMBER="42"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp -f "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Les bibliothèques livrent parfois des ressources (*.bundle) à côté du binaire.
for resource_bundle in "${BIN_DIR}"/*.bundle; do
    [ -e "${resource_bundle}" ] || continue
    cp -R -f "${resource_bundle}" "${APP_DIR}/Contents/Resources/"
done

# Le logo : l'image source 1024 px est réduite en toutes les tailles de l'icône avec les outils de macOS (sips, iconutil).
ICON_SOURCE="Resources/Encoche/AppIcon.png"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "${ICONSET_DIR}")"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Encoche reads the current track in Music and Spotify and sends them previous, pause and next.</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2024 Lakr Aream. Copyright © 2026 Yannick (yanmwisa). MIT License.</string>
</dict>
</plist>
PLIST

# Signature ad hoc : suffit pour un usage personnel sur ce Mac.
codesign --force --deep --sign - "${APP_DIR}"
echo "Application construite : ${APP_DIR}"
