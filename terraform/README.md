# Terraform

Infraestructura del proyecto en AWS (región `us-east-2`). Normalmente la aplica
el **Pipeline 1** ([`pipeline-1-infraestructura.yml`](../.github/workflows/pipeline-1-infraestructura.yml)),
pero también se puede ejecutar en local con los pasos de abajo.

## Contenido

| Archivo | Recursos |
|---|---|
| [`red.tf`](red.tf) | VPC `10.20.0.0/16`, 2 subredes públicas en 2 zonas, Internet Gateway y tabla de rutas |
| [`seguridad.tf`](seguridad.tf) | Security group del ALB (HTTP 80 desde Internet), security group de las tareas (solo desde el ALB), rol de ejecución de ECS |
| [`ecr.tf`](ecr.tf) | Repositorios `proyecto-final/frontend` y `proyecto-final/backend` (etiquetas inmutables, escaneo al subir, ciclo de vida) |
| [`alb.tf`](alb.tf) | Application Load Balancer, target groups, listener HTTP y regla `/api/*` → backend |
| [`ecs.tf`](ecs.tf) | Cluster ECS, logs de CloudWatch, definiciones de tarea iniciales y servicios Fargate (circuit breaker con rollback) |
| [`variables.tf`](variables.tf) / [`terraform.tfvars.example`](terraform.tfvars.example) | Variables y valores de ejemplo |
| [`outputs.tf`](outputs.tf) | URL de la aplicación, cluster, servicios y repositorios ECR |
| [`versions.tf`](versions.tf) | Versiones de Terraform/proveedor y backend S3 con bloqueo nativo |
| [`backend.hcl.example`](backend.hcl.example) | Configuración de ejemplo del estado remoto |
| [`bootstrap/`](bootstrap) | Se aplica **una sola vez** en local: bucket S3 del estado, usuario IAM de CI y roles `ci-infra` / `ci-app` |

## Requisitos

- Terraform >= 1.10 y AWS CLI v2 con sesión iniciada (`aws login`).
- Proyecto de AWS en la región `us-east-2`.

## Ejecución

### 1. Bootstrap (una sola vez)

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

Las salidas (`bucket_estado`, `rol_infra_arn`, `rol_app_arn`) son las variables
del repositorio en GitHub; el script `pipelines/scripts/crear-clave-ci.sh` las
carga junto con la clave de CI. El estado del bootstrap queda **solo en local**
(está en `.gitignore`): consérvelo.

### 2. Infraestructura principal

```bash
cd terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Edite `backend.hcl` y ponga en `bucket` el valor de `terraform output bucket_estado` del bootstrap. Después:

```bash
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
terraform output url_aplicacion
```

`backend.hcl` y `terraform.tfvars` están en `.gitignore` (el primero contiene el ID de cuenta).

### 3. Destruir

```bash
terraform destroy
```

O desde el pipeline:

```bash
gh workflow run "Pipeline 1 - Infraestructura (Terraform)" -f accion=destroy -f confirmar_destroy=DESTRUIR
```

## Notas

- Los servicios ECS se crean con `desired_count = 0` y Terraform ignora cambios en
  `task_definition` y `desired_count`: las versiones de la aplicación las gestiona
  el **Pipeline 3**, así que un `terraform apply` no revierte un despliegue.
- El estado está en S3 con versionado, cifrado y `use_lockfile` (bloqueo sin DynamoDB).
