#!/bin/bash
# Compila el paquete y ensambla build/<APP_NAME>.app.
#
#   Scripts/build-app.sh [debug|release]
#
# Variables opcionales:
#   SIGN_IDENTITY  identidad de firma. Por defecto, el certificado local
#                  "NotchFlow Dev" si está en el llavero (ver README) y, si
#                  no, "-" (firma ad-hoc). Para distribuir, el nombre de un
#                  certificado "Developer ID Application: …".
#
# Solo arm64: todos los MacBook con notch son Apple Silicon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../Config/app.env
source "$ROOT/Config/app.env"
: "${APP_NAME:?}" "${BUNDLE_ID:?}" "${APP_VERSION:?}" "${APP_BUILD:?}" "${MIN_MACOS:?}"

CONFIG="${1:-release}"
# Con firma ad-hoc cada compilación tiene otra huella y macOS olvida los
# permisos concedidos (calendario, cámara…). Un certificado fijo lo evita.
LOCAL_IDENTITY="NotchFlow Dev"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -p codesigning | grep -q "\"$LOCAL_IDENTITY\""; then
        SIGN_IDENTITY="$LOCAL_IDENTITY"
    else
        SIGN_IDENTITY="-"
    fi
fi

swift build --package-path "$ROOT" -c "$CONFIG" --product NotchApp
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchApp" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Adaptador de MediaRemote para el módulo de música (ver Vendor/mediaremote-adapter).
mkdir -p "$APP/Contents/Frameworks"
"$ROOT/Scripts/build-mediaremote-adapter.sh" "$APP/Contents/Frameworks"
cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$APP/Contents/Resources/mediaremote-adapter-LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>es</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>$APP_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>$APP_NAME muestra tus próximos eventos en el panel. Los datos del calendario no salen de tu Mac.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>$APP_NAME muestra tus tareas pendientes de Recordatorios y te permite añadirlas y completarlas.</string>
    <key>NSCameraUsageDescription</key>
    <string>$APP_NAME muestra la imagen de tu cámara como espejo solo cuando la enciendes en el panel. No se graba ni se envía nada.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>$APP_NAME muestra la canción que suena en Música y te permite pausar o cambiar de pista.</string>
</dict>
</plist>
EOF

# El código anidado se firma antes que la app que lo contiene. La notarización
# exige Hardened Runtime (--options runtime) y sello de tiempo de Apple, que no
# está disponible con la firma ad-hoc.
SIGN_FLAGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT/Config/NotchApp.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Creada: $APP"
