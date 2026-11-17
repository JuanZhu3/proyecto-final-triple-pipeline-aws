#!/usr/bin/env bash
# PIPELINE 3 - Despliega en ECS la imagen de ECR indicada para un componente:
#   1. Verifica que la imagen exista en ECR.
#   2. Toma la definición de tarea actual del servicio, cambia la imagen y la
#      variable APP_VERSION y registra una nueva revisión.
#   3. Actualiza el servicio (desired_count = 1) y espera a que quede estable.
#   4. Si ECS revierte el despliegue (circuit breaker), el script falla.
#
# Uso: desplegar.sh <frontend|backend> [etiqueta]
#      Sin etiqueta, usa la imagen publicada más reciente en ECR.
set -euo pipefail
source "$(dirname "$0")/comun.sh"

COMPONENTE="${1:?Uso: $0 <frontend|backend> [etiqueta]}"
ETIQUETA="${2:-}"
DESEADAS="${DESIRED_COUNT:-1}"
requiere aws jq

REPO="$(repo_de "$COMPONENTE")"
SERVICIO="$(servicio_de "$COMPONENTE")"

if [[ -z "$ETIQUETA" ]]; then
  ETIQUETA="$(aws ecr describe-images --repository-name "$REPO" --filter tagStatus=TAGGED \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text)"
  [[ "$ETIQUETA" != "None" && -n "$ETIQUETA" ]] || falla "No hay imágenes en $REPO. Ejecute el Pipeline 2."
  log "Sin etiqueta explícita: se usa la más reciente en ECR ($ETIQUETA)"
fi

imagen_existe "$COMPONENTE" "$ETIQUETA" || falla "La imagen $REPO:$ETIQUETA no existe en ECR."
IMAGEN="$(registro_ecr)/$REPO:$ETIQUETA"

log "Leyendo la definición de tarea actual de $SERVICIO"
TD_ACTUAL="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICIO" \
  --query 'services[0].taskDefinition' --output text)"
[[ "$TD_ACTUAL" != "None" ]] || falla "El servicio $SERVICIO no existe. Ejecute el Pipeline 1."

# Partimos de la última revisión de la familia: así también se aplican cambios
# hechos por Terraform (CPU, memoria, logs...) en la definición de tarea.
FAMILIA="$(aws ecs describe-task-definition --task-definition "$TD_ACTUAL" --query 'taskDefinition.family' --output text)"
TD_JSON="$(aws ecs describe-task-definition --task-definition "$FAMILIA" --query 'taskDefinition' --output json)"

NUEVA_TD="$(echo "$TD_JSON" | jq --arg img "$IMAGEN" --arg ver "$ETIQUETA" --arg c "$COMPONENTE" '
  .containerDefinitions |= map(
    if .name == $c then
      .image = $img
      | .environment = ((.environment // []) | map(select(.name != "APP_VERSION")) + [{name: "APP_VERSION", value: $ver}])
    else . end)
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
        .registeredAt, .registeredBy, .deregisteredAt)')"

TD_ARN="$(aws ecs register-task-definition --cli-input-json "$NUEVA_TD" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
log "Nueva definición de tarea: ${TD_ARN##*/}"

log "Actualizando el servicio $SERVICIO -> $IMAGEN"
DEPLOY_ID="$(aws ecs update-service --cluster "$CLUSTER" --service "$SERVICIO" \
  --task-definition "$TD_ARN" --desired-count "$DESEADAS" \
  --query 'service.deployments[?status==`PRIMARY`].id | [0]' --output text)"

log "Esperando a que el servicio esté estable (máx. ~10 min)..."
if ! aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICIO"; then
  error "El servicio $SERVICIO no se estabilizó. Últimos eventos:"
  aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICIO" \
    --query 'services[0].events[:8].[createdAt,message]' --output text >&2
  exit 1
fi

# El circuit breaker puede haber revertido a la revisión anterior: comprobarlo.
ESTADO="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICIO" --output json)"
TD_EN_EJECUCION="$(echo "$ESTADO" | jq -r '.services[0].deployments[] | select(.status=="PRIMARY") | .taskDefinition')"
ROLLOUT="$(echo "$ESTADO" | jq -r --arg id "$DEPLOY_ID" '.services[0].deployments[] | select(.id==$id) | .rolloutState' 2>/dev/null || true)"

if [[ "$TD_EN_EJECUCION" != "$TD_ARN" ]]; then
  error "ECS revirtió el despliegue de $SERVICIO (circuit breaker). Sigue en ${TD_EN_EJECUCION##*/}."
  echo "$ESTADO" | jq -r '.services[0].events[:8][] | "\(.createdAt) \(.message)"' >&2
  exit 1
fi

log "OK: $SERVICIO ejecuta ${TD_ARN##*/} (rollout: ${ROLLOUT:-COMPLETED})"
resumen "- \`$COMPONENTE\`: \`$SERVICIO\` → \`$REPO:$ETIQUETA\` (\`${TD_ARN##*/}\`) ✅"
