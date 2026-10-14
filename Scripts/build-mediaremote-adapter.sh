#!/bin/bash
# Compila Vendor/mediaremote-adapter como MediaRemoteAdapter.framework.
#
#   Scripts/build-mediaremote-adapter.sh DESTINO_DIR
#
# Equivale al objetivo de CMake del proyecto original, solo para arm64.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
DEST="${1:?Falta el directorio de destino}"
NAME="MediaRemoteAdapter"
FRAMEWORK="$DEST/$NAME.framework"
VERSION_DIR="$FRAMEWORK/Versions/A"

rm -rf "$FRAMEWORK"
mkdir -p "$VERSION_DIR/Resources"

clang -dynamiclib -arch arm64 -mmacosx-version-min=14.0 -O2 \
    -fobjc-arc -fvisibility=default \
    -I "$SRC/include" -I "$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -o "$VERSION_DIR/$NAME" \
    "$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m

cat > "$VERSION_DIR/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>com.vandenbe.$NAME</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
</dict>
</plist>
PLIST

ln -s A "$FRAMEWORK/Versions/Current"
ln -s "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -s "Versions/Current/Resources" "$FRAMEWORK/Resources"
