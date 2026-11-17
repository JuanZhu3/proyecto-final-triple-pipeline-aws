#!/usr/bin/env bash
# PIPELINE 3 - Prueba de humo: comprueba a través del ALB que el frontend y el
# backend responden y que ejecutan la versión esperada. Hace una operación de
# extremo a extremo (crear y borrar una tarea) por la API.
#
# Uso: prueba-humo.sh [version_esperada]
set -euo pipefail
source "$(dirname "$0")/comun.sh"
requiere aws curl jq

VERSION="${1:-}"
DNS="$(aws elbv2 describe-load-balancers --names "$ALB_NOMBRE" --query 'LoadBalancers[0].DNSName' --output text)"
URL="http://$DNS"
log "URL de la aplicación: $URL"

reintentar() { # reintenta un comando hasta 12 veces (≈2 min)
  local i
  for i in $(seq 1 12); do
    if "$@"; then return 0; fi
    log "Intento $i fallido; reintentando en 10 s..."
    sleep 10
  done
  return 1
}

comprobar_frontend() {
  local html; html="$(curl -fsS --max-time 10 "$URL/")" || return 1
  grep -q "Lista de tareas" <<<"$html" || return 1
  if [[ -n "$VERSION" ]]; then
    [[ "$(curl -fsS --max-time 10 "$URL/version.json" | jq -r .version)" == "$VERSION" ]] || return 1
  fi
}

comprobar_backend() {
  local health; health="$(curl -fsS --max-time 10 "$URL/api/health")" || return 1
  [[ "$(jq -r .estado <<<"$health")" == "ok" ]] || return 1
  if [[ -n "$VERSION" ]]; then
    [[ "$(jq -r .version <<<"$health")" == "$VERSION" ]] || return 1
  fi
}

log "Comprobando el frontend..."
reintentar comprobar_frontend || falla "El frontend no responde correctamente en $URL/"
log "Comprobando el backend..."
reintentar comprobar_backend || falla "El backend no responde correctamente en $URL/api/health"

log "Prueba de extremo a extremo de la API (crear y borrar una tarea)"
ID="$(curl -fsS --max-time 10 -X POST "$URL/api/tareas" -H 'Content-Type: application/json' \
  -d '{"titulo":"prueba de humo del pipeline"}' | jq -r .id)" || falla "No se pudo crear una tarea"
curl -fsS --max-time 10 -X DELETE "$URL/api/tareas/$ID" -o /dev/null || falla "No se pudo borrar la tarea $ID"

log "Aplicación operativa en $URL"
resumen "### ✅ Aplicación operativa"
resumen "- URL: $URL"
resumen "- Versión verificada: \`${VERSION:-no especificada}\`"
