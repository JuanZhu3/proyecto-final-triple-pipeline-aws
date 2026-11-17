# Pipelines

Los tres pipelines se ejecutan en **GitHub Actions**. Las definiciones están en
[`.github/workflows/`](../.github/workflows) (GitHub solo las lee de esa ruta) y
la lógica en los scripts de [`scripts/`](scripts), que también se pueden ejecutar
en local con credenciales de AWS.

| Pipeline | Workflow | Disparador | Qué hace |
|---|---|---|---|
| 1 · Infraestructura | [`pipeline-1-infraestructura.yml`](../.github/workflows/pipeline-1-infraestructura.yml) | push a `main` en `terraform/**`, PR (solo validación), manual (`plan`/`apply`/`destroy`) | `terraform fmt` → `validate` → `plan` → `apply` con estado remoto en S3 |
| 2 · Construcción | [`pipeline-2-construccion.yml`](../.github/workflows/pipeline-2-construccion.yml) | push a `main` en `aplicacion/**`, PR (solo pruebas), manual | pruebas del backend, compilación del frontend, `docker build`, etiqueta = SHA corto del commit, `docker push` a ECR, resultado del escaneo |
| 3 · Despliegue | [`pipeline-3-despliegue.yml`](../.github/workflows/pipeline-3-despliegue.yml) | al terminar con éxito el Pipeline 2 en `main`, manual (etiqueta opcional) | nueva revisión de la definición de tarea con la imagen de ECR, `update-service`, espera de estabilidad, prueba de humo por el ALB |

## Scripts

| Script | Pipeline | Descripción |
|---|---|---|
| `comun.sh` | todos | Nombres de recursos, logs y utilidades compartidas |
| `construir-publicar.sh <componente> <etiqueta>` | 2 | Build, tag y push de una imagen a ECR (idempotente: si la etiqueta ya existe, no hace nada) |
| `desplegar.sh <componente> [etiqueta]` | 3 | Registra la definición de tarea, actualiza el servicio y detecta rollbacks del circuit breaker |
| `prueba-humo.sh [versión]` | 3 | Comprueba frontend, `/api/health`, la versión desplegada y un alta/baja por la API |
| `crear-clave-ci.sh` | bootstrap | Crea (o rota) la clave del usuario de CI y la guarda directamente en GitHub Secrets |

## Credenciales

- El proyecto AWS (nueva experiencia de AWS) bloquea los proveedores OIDC con una
  SCP gestionada, así que no se puede usar OIDC de GitHub.
- En su lugar hay un usuario IAM `proyecto-final-github-ci` cuyo **único permiso
  es `sts:AssumeRole`** sobre dos roles:
  - `proyecto-final-ci-infra` (Pipeline 1): EC2/VPC, ECS, ECR, ELB y Logs en la
    región del proyecto; IAM solo para roles `proyecto-final-ecs-*` y solo puede
    adjuntarles `AmazonECSTaskExecutionRolePolicy` (evita escalada de privilegios).
  - `proyecto-final-ci-app` (Pipelines 2 y 3): push a los repos `proyecto-final/*`
    de ECR, registrar definiciones de tarea y actualizar servicios de ECS.
- La clave del usuario vive solo en **GitHub Secrets** (`AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`). Cada job la usa para obtener credenciales
  **temporales** (1 h) del rol correspondiente.
- Los ARN de los roles, la región y el bucket de estado son **variables** del
  repositorio (no son secretos).

## Manejo de errores

- **Pipeline 1**: `concurrency` impide dos ejecuciones simultáneas sobre el mismo
  estado; además S3 bloquea el estado (`use_lockfile`). `plan -detailed-exitcode`
  distingue error / sin cambios / cambios. `destroy` exige escribir `DESTRUIR`.
- **Pipeline 2**: si fallan las pruebas no se construye ninguna imagen. Las
  etiquetas de ECR son inmutables, así que un reintento no sobrescribe imágenes.
  Si el repositorio ECR no existe, el error indica ejecutar el Pipeline 1.
- **Pipeline 3**: solo corre si el Pipeline 2 terminó con éxito. Verifica que la
  imagen exista antes de desplegar. ECS tiene *deployment circuit breaker* con
  rollback: si las tareas nuevas no pasan el health check del ALB, ECS vuelve
  sola a la revisión anterior y el script lo detecta y falla mostrando los
  eventos del servicio. La prueba de humo reintenta durante ~2 minutos.
