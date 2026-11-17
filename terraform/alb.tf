# -----------------------------------------------------------------------------
# ALB: punto de acceso público. Enruta por ruta:
#   /api/*  -> target group del backend
#   resto   -> target group del frontend (acción por defecto)
# -----------------------------------------------------------------------------

resource "aws_lb" "principal" {
  name                       = "${var.proyecto}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.publica[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  for_each             = var.servicios
  name                 = "${var.proyecto}-${each.key}"
  port                 = each.value.puerto
  protocol             = "HTTP"
  target_type          = "ip" # requerido por Fargate (awsvpc)
  vpc_id               = aws_vpc.principal.id
  deregistration_delay = 15 # despliegues más rápidos

  health_check {
    path                = each.value.ruta_health
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.principal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["frontend"].arn
  }
}

resource "aws_lb_listener_rule" "por_ruta" {
  for_each     = { for nombre, s in var.servicios : nombre => s if length(s.patrones_alb) > 0 }
  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.prioridad

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.patrones_alb
    }
  }
}
