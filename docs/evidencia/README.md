# Evidencia de la demo

Despliegue del 17-11-2026, versión `d0a5ae6`.

| Archivo | Qué demuestra |
|---|---|
| [`01-historial-pipelines.txt`](01-historial-pipelines.txt) | Historial de ejecuciones de los 3 pipelines en GitHub Actions (`gh run list`), todas con éxito |
| `02-infraestructura-aws.png` | *(por agregar)* Consola de AWS: cluster ECS con los 2 servicios activos y el ALB con sus target groups sanos |
| `03-imagenes-ecr.png` | *(por agregar)* Consola de AWS: repositorios `proyecto-final/frontend` y `proyecto-final/backend` con la etiqueta `d0a5ae6` y su escaneo |
| [`04-aplicacion-en-ecs.png`](04-aplicacion-en-ecs.png) | La aplicación servida por el ALB: frontend y backend en ECS reportan la misma versión `d0a5ae6` |
| [`05-respuestas-api.txt`](05-respuestas-api.txt) | Respuestas reales de `/api/health`, `/version.json` y `/api/tareas` a través del ALB |

Ejecuciones del despliegue actual:
[Pipeline 1](https://github.com/JuanZhu3/proyecto-final-triple-pipeline-aws/actions/runs/44115268398) ·
[Pipeline 2](https://github.com/JuanZhu3/proyecto-final-triple-pipeline-aws/actions/runs/44116100569) ·
[Pipeline 3](https://github.com/JuanZhu3/proyecto-final-triple-pipeline-aws/actions/runs/44116951342)
