#!/bin/bash
# Envía el .dmg a la notarización de Apple y grapa el resultado.
#
#   Scripts/notarize.sh dist/NotchFlow-0.1.0.dmg
#
# Requisitos (ver README, "Distribución"):
#   - El .dmg y la app firmados con un certificado Developer ID Application.
#   - Un perfil de credenciales guardado en el llavero con:
#       xcrun notarytool store-credentials "notchflow-notary" \
#           --apple-id TU_APPLE_ID --team-id TU_TEAM_ID
#     (pide una contraseña de app de appleid.apple.com; no se guarda en el proyecto)
#
# Variable opcional: NOTARY_PROFILE (por defecto "notchflow-notary").
set -euo pipefail

DMG="${1:?Uso: Scripts/notarize.sh ruta/al/archivo.dmg}"
PROFILE="${NOTARY_PROFILE:-notchflow-notary}"

codesign --verify --strict "$DMG" || { echo "El .dmg no está firmado; genera el paquete con SIGN_IDENTITY." >&2; exit 1; }

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Notarizado y grapado: $DMG"
