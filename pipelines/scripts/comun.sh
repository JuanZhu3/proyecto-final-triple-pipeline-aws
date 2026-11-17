#!/usr/bin/env bash
# Funciones y valores comunes para los scripts de los pipelines.
set -euo pipefail

PROYECTO="${PROYECTO:-proyecto-final}"
AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

CLUSTER="${PROYECTO}-cluster"
ALB_NOMBRE="${PROYECTO}-alb"
COMPONENTES=(backend frontend)

log()   { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::error::$*"; return 0; }
falla() { error "$*"; exit 1; }

requiere() {
  for cmd in "$@"; do command -v "$cmd" >/dev/null || falla "Falta la herramienta '$cmd'"; done
}

cuenta_aws() { aws sts get-caller-identity --query Account --output text; }

registro_ecr() { echo "$(cuenta_aws).dkr.ecr.${AWS_REGION}.amazonaws.com"; }

repo_de() { echo "${PROYECTO}/$1"; }

servicio_de() { echo "${PROYECTO}-$1"; }

imagen_existe() { # $1 componente, $2 etiqueta
  aws ecr describe-images --repository-name "$(repo_de "$1")" --image-ids imageTag="$2" >/dev/null 2>&1
}

# Escribe un resumen en la página de la ejecución de GitHub Actions (si aplica).
resumen() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }
