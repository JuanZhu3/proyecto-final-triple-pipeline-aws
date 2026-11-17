#!/usr/bin/env bash
# PIPELINE 2 - Construye la imagen Docker de un componente, la etiqueta y la
# publica en Amazon ECR.
#
# Uso: construir-publicar.sh <frontend|backend> <etiqueta>
set -euo pipefail
source "$(dirname "$0")/comun.sh"

COMPONENTE="${1:?Uso: $0 <frontend|backend> <etiqueta>}"
ETIQUETA="${2:?Falta la etiqueta (p. ej. el SHA corto del commit)}"
[[ " ${COMPONENTES[*]} " == *" $COMPONENTE "* ]] || falla "Componente desconocido: $COMPONENTE"

requiere aws docker
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXTO="$RAIZ/aplicacion/$COMPONENTE"
REGISTRO="$(registro_ecr)"
REPO="$(repo_de "$COMPONENTE")"
IMAGEN="$REGISTRO/$REPO:$ETIQUETA"

aws ecr describe-repositories --repository-names "$REPO" >/dev/null 2>&1 \
  || falla "El repositorio ECR '$REPO' no existe. Ejecute primero el Pipeline 1 (infraestructura)."

# Las etiquetas son inmutables: si ya existe, no se vuelve a publicar (idempotente).
if imagen_existe "$COMPONENTE" "$ETIQUETA"; then
  log "La imagen $REPO:$ETIQUETA ya existe en ECR; se omite la publicación."
  resumen "- \`$COMPONENTE\`: \`$ETIQUETA\` ya existía en ECR (sin cambios)"
  exit 0
fi

log "Login en ECR ($REGISTRO)"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRO"

log "Construyendo $IMAGEN"
# --provenance=false: publica un manifiesto simple (sin attestations de BuildKit).
# Así el escaneo básico de ECR puede analizar la imagen y la regla de ciclo de
# vida "untagged" no borra piezas de una imagen etiquetada.
docker build \
  --platform linux/amd64 \
  --provenance=false \
  --build-arg APP_VERSION="$ETIQUETA" \
  --label org.opencontainers.image.revision="${GITHUB_SHA:-local}" \
  --label org.opencontainers.image.source="${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-local}" \
  -t "$IMAGEN" "$CONTEXTO"

log "Publicando $IMAGEN"
docker push "$IMAGEN"

DIGEST="$(aws ecr describe-images --repository-name "$REPO" --image-ids imageTag="$ETIQUETA" \
  --query 'imageDetails[0].imageDigest' --output text)"
log "Publicada: $REPO:$ETIQUETA ($DIGEST)"

# Resultado del escaneo de vulnerabilidades (informativo, no bloquea).
log "Esperando el escaneo de vulnerabilidades de ECR..."
if aws ecr wait image-scan-complete --repository-name "$REPO" --image-id imageTag="$ETIQUETA" 2>/dev/null; then
  HALLAZGOS="$(aws ecr describe-image-scan-findings --repository-name "$REPO" --image-id imageTag="$ETIQUETA" \
    --query 'imageScanFindings.findingSeverityCounts' --output json)"
  log "Hallazgos del escaneo: $HALLAZGOS"
else
  HALLAZGOS="(escaneo no disponible)"
fi

resumen "- \`$COMPONENTE\`: \`$REPO:$ETIQUETA\` publicada · digest \`${DIGEST:0:19}…\` · escaneo: \`$(echo "$HALLAZGOS" | tr -d '\n ')\`"
