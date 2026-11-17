# -----------------------------------------------------------------------------
# ECS FARGATE: cluster, definiciones de tarea iniciales y servicios.
#
# Separación de responsabilidades entre pipelines:
#   - Terraform (Pipeline 1) crea los servicios con desired_count = 0 y una
#     definición de tarea "plantilla" (imagen con etiqueta `inicial`, que nunca
#     se ejecuta).
#   - El Pipeline 3 registra nuevas revisiones con la imagen real (etiqueta =
#     SHA del commit), sube desired_count a 1 y espera a que el servicio esté
#     estable. Por eso Terraform ignora `task_definition` y `desired_count`.
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "principal" {
  name = "${var.proyecto}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled" # ahorro de costos; se pueden ver logs en CloudWatch Logs
  }
}

resource "aws_cloudwatch_log_group" "app" {
  for_each          = var.servicios
  name              = "/ecs/${var.proyecto}/${each.key}"
  retention_in_days = var.retencion_logs_dias
}

resource "aws_ecs_task_definition" "app" {
  for_each                 = var.servicios
  family                   = "${var.proyecto}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memoria
  execution_role_arn       = aws_iam_role.ejecucion_tareas.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = each.key
    image        = "${aws_ecr_repository.app[each.key].repository_url}:inicial"
    essential    = true
    portMappings = [{ containerPort = each.value.puerto, protocol = "tcp" }]
    environment  = [{ name = "APP_VERSION", value = "inicial" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  for_each                           = var.servicios
  name                               = "${var.proyecto}-${each.key}"
  cluster                            = aws_ecs_cluster.principal.id
  task_definition                    = aws_ecs_task_definition.app[each.key].arn
  desired_count                      = 0
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"

  # Si un despliegue no logra tareas sanas, ECS lo detiene y vuelve a la
  # última revisión que funcionaba (manejo de errores en el despliegue).
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.publica[*].id
    security_groups  = [aws_security_group.tareas.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app[each.key].arn
    container_name   = each.key
    container_port   = each.value.puerto
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener_rule.por_ruta]
}
