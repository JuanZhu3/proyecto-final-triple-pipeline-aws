#!/usr/bin/env bash
# Prepara una computadora macOS (o Linux con Homebrew) para presentar / operar el proyecto.
# Uso:
#   bash pipelines/scripts/preparar-computadora.sh
# o, sin haber clonado aún el repositorio:
#   curl -fsSL https://raw.githubusercontent.com/JuanZhu3/proyecto-final-triple-pipeline-aws/main/pipelines/scripts/preparar-computadora.sh | bash
# Es idempotente: se puede ejecutar varias veces.
set -euo pipefail

REPO="JuanZhu3/proyecto-final-triple-pipeline-aws"
PERFIL="proyecto-final"
REGION="us-east-2"
DESTINO="$HOME/proyecto-final-triple-pipeline-aws"

paso() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }

paso "1/6 Instalando herramientas con Homebrew"
if ! command -v brew >/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
fi
brew install git gh awscli node hashicorp/tap/terraform
brew upgrade awscli || true   # `aws login` requiere una versión reciente
if [ "$(uname)" = "Darwin" ] && ! command -v docker >/dev/null; then
  brew install --cask docker   # solo para correr la app en local
fi

paso "2/6 Iniciando sesión en GitHub (se abre el navegador)"
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
git config --global user.name  >/dev/null || git config --global user.name  "$(gh api user --jq '.name // .login')"
git config --global user.email >/dev/null || git config --global user.email "$(gh api user --jq '.id')+$(gh api user --jq '.login')@users.noreply.github.com"

paso "3/6 Clonando el repositorio en $DESTINO"
if [ -d "$DESTINO/.git" ]; then
  git -C "$DESTINO" checkout main && git -C "$DESTINO" pull --ff-only
else
  gh repo clone "$REPO" "$DESTINO"
fi

paso "4/6 Iniciando sesión en AWS (perfil $PERFIL, región $REGION; se abre el navegador)"
aws configure set region "$REGION" --profile "$PERFIL"
aws sts get-caller-identity --profile "$PERFIL" >/dev/null 2>&1 || aws login --profile "$PERFIL"
CUENTA=$(aws sts get-caller-identity --profile "$PERFIL" --query Account --output text)
echo "  Cuenta AWS: $CUENTA"
export AWS_PROFILE="$PERFIL"
RC="$HOME/.bashrc"; [ "$(uname)" = "Darwin" ] && RC="$HOME/.zshrc"
grep -q "AWS_PROFILE=$PERFIL" "$RC" 2>/dev/null || echo "export AWS_PROFILE=$PERFIL" >> "$RC"

paso "5/6 Configuración local de Terraform (backend.hcl, ignorado por git)"
cat > "$DESTINO/terraform/backend.hcl" <<EOF
bucket = "proyecto-final-tfstate-$CUENTA-$REGION"
key    = "infra/terraform.tfstate"
region = "$REGION"
EOF
(cd "$DESTINO/terraform" && terraform init -backend-config=backend.hcl -input=false >/dev/null)

paso "6/6 Verificación"
(cd "$DESTINO/aplicacion/backend" && npm ci --silent && npm test)
git --version; gh --version | head -1; aws --version; terraform version | head -1; node --version
gh workflow list --repo "$REPO"
aws elbv2 describe-load-balancers --names proyecto-final-alb \
  --query "LoadBalancers[0].DNSName" --output text 2>/dev/null \
  || echo "  (La infraestructura no está creada: ejecute el Pipeline 1 con accion=apply antes de la demo)"

printf '\n\033[32mListo. Abra una terminal nueva para que AWS_PROFILE quede activo.\033[0m\n'
