# Prepara una computadora Windows para presentar / operar el proyecto.
# Uso (PowerShell normal, no hace falta administrador):
#   powershell -ExecutionPolicy Bypass -File pipelines\scripts\preparar-computadora.ps1
# o, sin haber clonado aún el repositorio:
#   irm https://raw.githubusercontent.com/JuanZhu3/proyecto-final-triple-pipeline-aws/main/pipelines/scripts/preparar-computadora.ps1 | iex
# Es idempotente: se puede ejecutar varias veces.

$ErrorActionPreference = "Continue"   # los comandos nativos que fallan se revisan con $LASTEXITCODE
$Repo     = "JuanZhu3/proyecto-final-triple-pipeline-aws"
$Perfil   = "proyecto-final"
$Region   = "us-east-2"
$Destino  = Join-Path $HOME "proyecto-final-triple-pipeline-aws"

function Paso($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Refrescar-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User")
}

Paso "1/6 Instalando herramientas con winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "No se encontró winget. Instale 'App Installer' desde Microsoft Store y vuelva a ejecutar."
}
$paquetes = @(
  @{ id = "Git.Git";              cmd = "git" },
  @{ id = "GitHub.cli";           cmd = "gh" },
  @{ id = "Amazon.AWSCLI";        cmd = "aws" },
  @{ id = "Hashicorp.Terraform";  cmd = "terraform" },
  @{ id = "OpenJS.NodeJS.LTS";    cmd = "node" },
  @{ id = "Docker.DockerDesktop"; cmd = "docker" }   # solo para correr la app en local
)
foreach ($p in $paquetes) {
  Refrescar-Path
  if (Get-Command $p.cmd -ErrorAction SilentlyContinue) {
    Write-Host "  $($p.cmd) ya instalado"
  } else {
    winget install --id $p.id -e --accept-package-agreements --accept-source-agreements
  }
}
# Actualiza AWS CLI: `aws login` requiere una versión reciente
winget upgrade --id Amazon.AWSCLI -e --accept-package-agreements --accept-source-agreements 2>$null
Refrescar-Path

Paso "2/6 Iniciando sesión en GitHub (se abre el navegador)"
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) { gh auth login --hostname github.com --git-protocol https --web }
gh auth setup-git
if (-not (git config --global user.name))  { git config --global user.name  (gh api user --jq ".name // .login") }
if (-not (git config --global user.email)) { git config --global user.email ((gh api user --jq ".id") + "+" + (gh api user --jq ".login") + "@users.noreply.github.com") }

Paso "3/6 Clonando el repositorio en $Destino"
if (Test-Path (Join-Path $Destino ".git")) {
  git -C $Destino checkout main; git -C $Destino pull --ff-only
} else {
  gh repo clone $Repo $Destino
}

Paso "4/6 Iniciando sesión en AWS (perfil $Perfil, región $Region; se abre el navegador)"
aws configure set region $Region --profile $Perfil
aws sts get-caller-identity --profile $Perfil 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { aws login --profile $Perfil }
$Cuenta = aws sts get-caller-identity --profile $Perfil --query Account --output text
Write-Host "  Cuenta AWS: $Cuenta"
[Environment]::SetEnvironmentVariable("AWS_PROFILE", $Perfil, "User")
$env:AWS_PROFILE = $Perfil

Paso "5/6 Configuración local de Terraform (backend.hcl, ignorado por git)"
$hcl = Join-Path $Destino "terraform\backend.hcl"
@"
bucket = "proyecto-final-tfstate-$Cuenta-$Region"
key    = "infra/terraform.tfstate"
region = "$Region"
"@ | Set-Content -Encoding ascii $hcl
Push-Location (Join-Path $Destino "terraform")
terraform init -backend-config=backend.hcl -input=false | Out-Null
Pop-Location

Paso "6/6 Verificación"
Push-Location (Join-Path $Destino "aplicacion\backend"); npm ci --silent; npm test; Pop-Location
git --version; gh --version | Select-Object -First 1; aws --version
terraform version | Select-Object -First 1; node --version
gh workflow list --repo $Repo
aws elbv2 describe-load-balancers --names proyecto-final-alb --query "LoadBalancers[0].DNSName" --output text 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  (La infraestructura no está creada: ejecute el Pipeline 1 con accion=apply antes de la demo)" -ForegroundColor Yellow }

Write-Host "`nListo. Docker Desktop puede pedir reiniciar la sesión la primera vez." -ForegroundColor Green
