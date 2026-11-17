# -----------------------------------------------------------------------------
# SEGURIDAD: security groups (Internet -> ALB -> tareas) y rol de ejecución.
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.proyecto}-alb-sg"
  description = "Trafico HTTP publico hacia el ALB"
  vpc_id      = aws_vpc.principal.id
  tags        = { Name = "${var.proyecto}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_a_tareas" {
  for_each                     = var.servicios
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB hacia ${each.key}"
  referenced_security_group_id = aws_security_group.tareas.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.puerto
  to_port                      = each.value.puerto
}

resource "aws_security_group" "tareas" {
  name        = "${var.proyecto}-tareas-sg"
  description = "Tareas de ECS: solo aceptan trafico del ALB"
  vpc_id      = aws_vpc.principal.id
  tags        = { Name = "${var.proyecto}-tareas-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "tareas_desde_alb" {
  for_each                     = var.servicios
  security_group_id            = aws_security_group.tareas.id
  description                  = "${each.key} desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.puerto
  to_port                      = each.value.puerto
}

# Salida HTTPS: necesaria para descargar imágenes de ECR y enviar logs a CloudWatch.
resource "aws_vpc_security_group_egress_rule" "tareas_https" {
  security_group_id = aws_security_group.tareas.id
  description       = "HTTPS saliente (ECR, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Rol de ejecución de tareas: permite a ECS descargar imágenes y escribir logs.
data "aws_iam_policy_document" "confianza_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.actual.account_id}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.actual.account_id]
    }
  }
}

data "aws_caller_identity" "actual" {}

resource "aws_iam_role" "ejecucion_tareas" {
  name               = "${var.proyecto}-ecs-ejecucion"
  assume_role_policy = data.aws_iam_policy_document.confianza_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "ejecucion_tareas" {
  role       = aws_iam_role.ejecucion_tareas.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
