# -----------------------------------------------------------------------------
# BOOTSTRAP (se ejecuta UNA vez, a mano, con credenciales del dueño del proyecto)
#
# Crea lo que los pipelines necesitan antes de poder ejecutarse:
#   1. Bucket S3 para el estado remoto de Terraform (con bloqueo nativo de S3).
#   2. Usuario IAM de CI cuyo ÚNICO permiso es asumir los dos roles de abajo.
#      (El proyecto AWS bloquea los proveedores OIDC con una SCP gestionada,
#       por eso no se usa OIDC de GitHub.)
#   3. Rol "infra"  -> lo usa el Pipeline 1 (Terraform).
#   4. Rol "app"    -> lo usan los Pipelines 2 (push a ECR) y 3 (deploy a ECS).
#
# La clave de acceso del usuario NO se crea aquí (quedaría en el tfstate);
# la crea scripts/crear-clave-ci.sh y la guarda directo en GitHub Secrets.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "actual" {}

locals {
  cuenta       = data.aws_caller_identity.actual.account_id
  bucket_state = "${var.proyecto}-tfstate-${local.cuenta}-${var.region}"
  prefijo_rol  = "arn:aws:iam::${local.cuenta}:role/${var.proyecto}-ecs-*"
}

# ---------------------------- Estado remoto ----------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_state
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ---------------------------- Usuario de CI ----------------------------------
resource "aws_iam_user" "ci" {
  name = "${var.proyecto}-github-ci"
}

resource "aws_iam_user_policy" "ci_solo_asumir_roles" {
  name = "solo-asumir-roles-ci"
  user = aws_iam_user.ci.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = [aws_iam_role.infra.arn, aws_iam_role.app.arn]
    }]
  })
}

data "aws_iam_policy_document" "confianza_ci" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.ci.arn]
    }
  }
}

# ------------------- Rol INFRA (Pipeline 1: Terraform) -----------------------
resource "aws_iam_role" "infra" {
  name                 = "${var.proyecto}-ci-infra"
  description          = "Pipeline 1: terraform plan/apply de la infraestructura"
  assume_role_policy   = data.aws_iam_policy_document.confianza_ci.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "infra" {
  statement {
    sid       = "ServiciosDeLaInfraEnLaRegion"
    actions   = ["ec2:*", "ecs:*", "ecr:*", "elasticloadbalancing:*", "logs:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "LecturaIAM"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "GestionarRolesDeECSDelProyecto"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:DetachRolePolicy",
    ]
    resources = [local.prefijo_rol]
  }

  # Evita escalada de privilegios: solo puede adjuntar la política gestionada de ejecución de ECS.
  statement {
    sid       = "AdjuntarSoloPoliticaDeEjecucionECS"
    actions   = ["iam:AttachRolePolicy"]
    resources = [local.prefijo_rol]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "PasarRolesSoloAECS"
    actions   = ["iam:PassRole"]
    resources = [local.prefijo_rol]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "RolesVinculadosAServicio"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "EstadoTerraformListar"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  statement {
    sid       = "EstadoTerraformObjetos"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
}

resource "aws_iam_role_policy" "infra" {
  name   = "permisos-terraform"
  role   = aws_iam_role.infra.id
  policy = data.aws_iam_policy_document.infra.json
}

# --------------- Rol APP (Pipelines 2 y 3: ECR + ECS deploy) -----------------
resource "aws_iam_role" "app" {
  name                 = "${var.proyecto}-ci-app"
  description          = "Pipelines 2 y 3: publicar imagenes en ECR y desplegar en ECS"
  assume_role_policy   = data.aws_iam_policy_document.confianza_ci.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "LoginECR"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushPullRepositoriosDelProyecto"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.cuenta}:repository/${var.proyecto}/*"]
  }

  statement {
    sid = "DesplegarEnECS"
    actions = [
      "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition",
      "ecs:DescribeServices", "ecs:UpdateService", "ecs:ListTasks", "ecs:DescribeTasks",
      "ecs:DescribeClusters",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "PasarRolesSoloAECS"
    actions   = ["iam:PassRole"]
    resources = [local.prefijo_rol]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "LeerALBParaSmokeTest"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeTargetGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "permisos-ecr-ecs"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}
