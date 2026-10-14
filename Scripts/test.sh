#!/bin/bash
# Ejecuta las pruebas unitarias.
#
# Con solo las Command Line Tools (Swift 6.4), la compilación de las pruebas
# falla de forma intermitente con "plugin for module 'TestingMacros' not found"
# sin que haya cambiado nada. No es un fallo del proyecto: repetir el comando
# acaba compilando. Este script reintenta solo en ese caso concreto; cualquier
# otro error o prueba fallida se devuelve tal cual.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp -t notch-tests)"
trap 'rm -f "$LOG"' EXIT

for attempt in 1 2 3 4 5 6; do
    swift test --package-path "$ROOT" "$@" > "$LOG" 2>&1
    status=$?
    if [ "$status" -ne 0 ] && grep -q "plugin for module 'TestingMacros' not found" "$LOG"; then
        echo "Intento $attempt: fallo del plugin de macros de la toolchain; se reintenta." >&2
        continue
    fi
    cat "$LOG"
    exit "$status"
done

cat "$LOG"
echo "El plugin de macros de Swift Testing siguió fallando tras varios intentos." >&2
exit 1
