output "bucket_estado" {
  description = "Bucket S3 del estado remoto (variable de GitHub TF_STATE_BUCKET)"
  value       = aws_s3_bucket.tfstate.bucket
}

output "rol_infra_arn" {
  description = "Rol del Pipeline 1 (variable de GitHub AWS_ROLE_INFRA_ARN)"
  value       = aws_iam_role.infra.arn
}

output "rol_app_arn" {
  description = "Rol de los Pipelines 2 y 3 (variable de GitHub AWS_ROLE_APP_ARN)"
  value       = aws_iam_role.app.arn
}

output "usuario_ci" {
  description = "Usuario IAM de CI (su clave se crea con scripts/crear-clave-ci.sh)"
  value       = aws_iam_user.ci.name
}
