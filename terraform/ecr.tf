# -----------------------------------------------------------------------------
# ECR: un repositorio por componente. Etiquetas INMUTABLES (cada imagen se
# etiqueta con el SHA del commit), escaneo de vulnerabilidades al publicar y
# política de ciclo de vida para no acumular imágenes.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  for_each             = var.servicios
  name                 = "${var.proyecto}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # permite `terraform destroy` aunque haya imágenes

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Borrar imagenes sin etiqueta tras 1 dia"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Conservar solo las ultimas ${var.imagenes_a_conservar} imagenes"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.imagenes_a_conservar }
        action       = { type = "expire" }
      }
    ]
  })
}
