#!/usr/bin/env bash
# BOOTSTRAP - Crea una clave de acceso para el usuario IAM de CI y la guarda
# DIRECTAMENTE como secrets cifrados del repositorio de GitHub, sin mostrarla
# ni escribirla en disco. También registra las variables (no secretas) que
# usan los workflows.
#
# Requisitos: aws (con credenciales del dueño del proyecto), gh (autenticado),
#             terraform/bootstrap ya aplicado.
# Uso: pipelines/scripts/crear-clave-ci.sh
set -euo pipefail
source "$(dirname "$0")/comun.sh"
requiere aws gh terraform

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
TF_BOOT=(terraform -chdir="$RAIZ/terraform/bootstrap" output -raw)
USUARIO="$("${TF_BOOT[@]}" usuario_ci)"

# Un usuario IAM admite como máximo 2 claves: rotamos borrando las anteriores.
for vieja in $(aws iam list-access-keys --user-name "$USUARIO" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  log "Eliminando clave anterior ${vieja:0:8}…"
  aws iam delete-access-key --user-name "$USUARIO" --access-key-id "$vieja"
done

log "Creando clave nueva para $USUARIO y guardándola en GitHub Secrets"
read -r ID_CLAVE SECRETO < <(aws iam create-access-key --user-name "$USUARIO" \
  --query "AccessKey.[AccessKeyId,SecretAccessKey]" --output text)
printf %s "$ID_CLAVE" | gh secret set AWS_ACCESS_KEY_ID
printf %s "$SECRETO"  | gh secret set AWS_SECRET_ACCESS_KEY
unset ID_CLAVE SECRETO

gh variable set AWS_REGION         --body "$AWS_REGION"
gh variable set TF_STATE_BUCKET    --body "$("${TF_BOOT[@]}" bucket_estado)"
gh variable set AWS_ROLE_INFRA_ARN --body "$("${TF_BOOT[@]}" rol_infra_arn)"
gh variable set AWS_ROLE_APP_ARN   --body "$("${TF_BOOT[@]}" rol_app_arn)"

log "Listo. Secrets y variables configurados en $(gh repo view --json nameWithOwner -q .nameWithOwner)"
