#!/bin/bash
# Genera una versión de prueba lista para compartir en dist/:
#   <APP_NAME>-<versión>.zip  y  <APP_NAME>-<versión>.dmg
#
#   Scripts/package.sh
#
# Usa la firma indicada en SIGN_IDENTITY (ver build-app.sh). Sin certificado
# Developer ID y sin notarizar, quien la reciba verá avisos de Gatekeeper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../Config/app.env
source "$ROOT/Config/app.env"

"$ROOT/Scripts/build-app.sh" release

APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/dist"
BASE="$APP_NAME-$APP_VERSION"
mkdir -p "$DIST"
rm -f "$DIST/$BASE.zip" "$DIST/$BASE.dmg"

# ditto conserva firmas, enlaces simbólicos y atributos del paquete.
ditto -c -k --keepParent "$APP" "$DIST/$BASE.zip"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Aplicaciones"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DIST/$BASE.dmg"
if [[ "${SIGN_IDENTITY:--}" == "Developer ID Application"* ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$BASE.dmg"
fi

echo "Creados:"
ls -lh "$DIST/$BASE.zip" "$DIST/$BASE.dmg"
