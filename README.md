# Proyecto Final: Tres Pipelines DevOps en AWS

Aplicación web **Lista de tareas** (frontend + API REST) que se aprovisiona,
construye y despliega en **Amazon ECS Fargate** mediante tres pipelines de
**GitHub Actions**, con la infraestructura definida en **Terraform**.

## Estructura

| Carpeta | Contenido |
|---|---|
| [`terraform/`](terraform) | Infraestructura como código: VPC, security groups, ECR, ALB, ECS Fargate. [`terraform/bootstrap/`](terraform/bootstrap): estado remoto y credenciales de CI |
| [`aplicacion/`](aplicacion) | [`frontend/`](aplicacion/frontend) (HTML/JS + nginx), [`backend/`](aplicacion/backend) (Node.js/Express + pruebas), Dockerfiles y `docker-compose.yml` para local |
| [`pipelines/`](pipelines) | Scripts de los tres pipelines y su documentación ([`pipelines/README.md`](pipelines/README.md)) |
| [`.github/workflows/`](.github/workflows) | Definiciones de los pipelines 1, 2 y 3 en GitHub Actions |

## Arquitectura

```
                         GitHub (repositorio)
   push terraform/** ─┐        │ push aplicacion/**
                      ▼        ▼
            ┌─────────────┐  ┌──────────────────┐ éxito ┌──────────────────┐
            │ Pipeline 1  │  │ Pipeline 2       │──────▶│ Pipeline 3       │
            │ Terraform   │  │ test·build·push  │       │ deploy · smoke   │
            └──────┬──────┘  └────────┬─────────┘       └────────┬─────────┘
       rol ci-infra│         rol ci-app│                 rol ci-app│
                   ▼                   ▼                           ▼
 ┌──────────────────────────── AWS · us-east-2 ─────────────────────────────┐
 │  S3 (estado TF)        ECR: proyecto-final/frontend, proyecto-final/backend │
 │                                     │ imágenes :<sha>                      │
 │  VPC 10.20.0.0/16 ─ 2 subredes públicas (2 AZ) ─ Internet Gateway         │
 │                                     ▼                                     │
 │  Internet ──HTTP:80──▶ ALB ──/api/*──▶ Servicio ECS backend  (Fargate :3000)│
 │                          └──── /* ───▶ Servicio ECS frontend (Fargate :8080)│
 │                                     │                                     │
 │                         CloudWatch Logs /ecs/proyecto-final/*             │
 └───────────────────────────────────────────────────────────────────────────┘
```

**Flujo de una petición:** el navegador carga el frontend (nginx) a través del
ALB; el JavaScript llama a `/api/tareas` con rutas relativas y el ALB envía
`/api/*` al servicio backend. Así ambos comparten origen (sin CORS) y el
frontend no necesita conocer la URL del backend.

### Decisiones de arquitectura

| Decisión | Motivo |
|---|---|
| **GitHub Actions** para los 3 pipelines | El código ya vive en GitHub; los workflows quedan versionados junto al código. |
| **ECS Fargate** sin servidores EC2 | No hay que administrar instancias; se paga por tarea. |
| **Un ALB con reglas por ruta** | Un único punto de entrada para frontend y backend, health checks por servicio. |
| **Subredes públicas sin NAT Gateway** | Un NAT cuesta ~32 USD/mes. Las tareas tienen IP pública solo para salir a ECR/CloudWatch; su security group **solo acepta tráfico del ALB**. En producción se usarían subredes privadas + NAT o VPC endpoints. |
| **Etiquetas de imagen = SHA del commit, inmutables** | Trazabilidad (cada contenedor sabe qué commit ejecuta) e imposibilidad de sobrescribir una imagen publicada. |
| **Terraform crea los servicios con `desired_count = 0` e ignora `task_definition`** | Separa responsabilidades: Terraform gestiona la infraestructura y el Pipeline 3 las versiones de la aplicación, sin que un `terraform apply` revierta un despliegue. |
| **Circuit breaker con rollback** en ECS | Si una versión nueva no pasa los health checks, ECS vuelve a la anterior automáticamente. |
| **Estado de Terraform en S3** con versionado, cifrado y bloqueo nativo | Permite ejecutar Terraform desde el pipeline y evita ejecuciones concurrentes. |
| **Datos en memoria** en el backend | Mantiene el foco en los pipelines. Los datos se pierden al redesplegar (se ve en la demo como efecto de un despliegue nuevo). |

### Manejo de credenciales

- **Ningún secreto en el repositorio.** `.gitignore` excluye `*.tfstate`,
  `*.tfvars`, `backend.hcl`, `.env` y claves.
- El proyecto AWS bloquea OIDC (SCP gestionada `iam:*Provider*`), por eso se usa
  un **usuario IAM de CI cuyo único permiso es asumir dos roles**. Su clave está
  solo en **GitHub Secrets**; cada job obtiene credenciales **temporales** del
  rol que necesita (`ci-infra` para Terraform, `ci-app` para ECR/ECS).
- Los roles tienen **mínimo privilegio**: limitados a la región del proyecto, a
  los repos `proyecto-final/*` y a roles `proyecto-final-ecs-*`.
- Los contenedores corren **sin root** y el rol de ejecución de ECS solo puede
  descargar imágenes y escribir logs.

Detalle de manejo de errores por pipeline en [`pipelines/README.md`](pipelines/README.md#manejo-de-errores).

## Requisitos

- Proyecto de AWS en la región `us-east-2` y AWS CLI v2 con sesión iniciada (`aws login`).
- Terraform >= 1.10, Git, GitHub CLI (`gh`) autenticado, Node.js >= 20.
- Docker (solo para ejecutar la aplicación en local).

## Reproducción

1. **Bootstrap (una sola vez, en local):** crea el bucket del estado, el usuario de CI y los roles.
   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply
   cd ../..
   ```
2. **Credenciales de CI:** crea la clave del usuario de CI y la guarda en GitHub Secrets, junto con las variables del repositorio.
   ```bash
   bash pipelines/scripts/crear-clave-ci.sh
   ```
3. **Pipeline 1:** haga push de cambios en `terraform/` o ejecútelo a mano:
   ```bash
   gh workflow run "Pipeline 1 - Infraestructura (Terraform)" -f accion=apply
   ```
4. **Pipeline 2 → 3:** un push a `main` que cambie `aplicacion/` construye y publica las imágenes, y al terminar despliega automáticamente. A mano:
   ```bash
   gh workflow run "Pipeline 2 - Construcción y publicación (ECR)"
   ```
   ```bash
   gh workflow run "Pipeline 3 - Despliegue (ECS)"
   ```
5. **URL de la aplicación:** aparece en el resumen de los pipelines 1 y 3, o con:
   ```bash
   aws elbv2 describe-load-balancers --names proyecto-final-alb --query "LoadBalancers[0].DNSName" --output text
   ```

### Ejecutar en local

```bash
cd aplicacion && docker compose up --build
```
Abra http://localhost:8000. Pruebas del backend: `cd aplicacion/backend && npm ci && npm test`.

### Destruir la infraestructura (tras la demo)

```bash
gh workflow run "Pipeline 1 - Infraestructura (Terraform)" -f accion=destroy -f confirmar_destroy=DESTRUIR
```
Después, opcionalmente, `terraform destroy` en `terraform/bootstrap` (borra el usuario de CI y el bucket del estado; vacíe antes el bucket).

### Costo aproximado

ALB (~0.55 USD/día) + 2 tareas Fargate de 0.25 vCPU / 0.5 GB (~0.60 USD/día) +
IPv4 públicas (~0.50 USD/día) ≈ **1.6 USD/día** mientras está desplegado.

## Demo

**Aplicación desplegada:** http://proyecto-final-alb-1627667169.us-east-2.elb.amazonaws.com
(disponible mientras la infraestructura no se destruya).

**Evidencia:** historial de ejecuciones en la pestaña
[Actions](https://github.com/JuanZhu3/proyecto-final-triple-pipeline-aws/actions) del repositorio.
Primera ejecución completa (17-11-2026):

| Pipeline | Resultado |
|---|---|
| 1 · Infraestructura | `terraform apply`: 33 recursos creados en ~4 min |
| 2 · Construcción | pruebas OK, imágenes `frontend` y `backend` publicadas en ECR con etiqueta = SHA del commit |
| 3 · Despliegue | ambos servicios estables en ECS, prueba de humo OK (versión verificada en `/version.json` y `/api/health`) |

Un cambio posterior en el CSS del frontend recorrió de forma automática
Pipeline 2 → Pipeline 3 y quedó en producción sin pasos manuales.

### Guion sugerido para la demo en vivo (~10 min)

1. **Código y arquitectura:** recorrer las carpetas y el diagrama de este README.
2. **Pipeline 1:** en *Actions*, ejecutar *Pipeline 1* con `accion=plan` (muestra
   "No changes", la infraestructura ya existe). En la consola de AWS mostrar la
   VPC, el ALB con sus 2 reglas, el cluster ECS y los target groups sanos.
3. **Pipeline 2:** hacer un cambio visible (p. ej. el subtítulo en
   `aplicacion/frontend/src/index.html`), commit y push a `main`. Mostrar las
   pruebas, el build y el push. En ECR mostrar la nueva etiqueta y el escaneo.
4. **Pipeline 3:** se dispara solo. Mostrar la nueva revisión de la definición
   de tarea, el despliegue *rolling* en ECS y la prueba de humo.
5. **Aplicación:** recargar la URL: el cambio y la nueva versión aparecen en la
   barra de estado; crear, completar y borrar tareas (frontend → API).
6. **Errores y credenciales:** explicar el circuit breaker con rollback, las
   etiquetas inmutables, los roles acotados y que la clave de CI solo existe en
   GitHub Secrets (ver [Manejo de credenciales](#manejo-de-credenciales)).
