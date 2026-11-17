output "url_aplicacion" {
  description = "URL pública de la aplicación (ALB)"
  value       = "http://${aws_lb.principal.dns_name}"
}

output "cluster_ecs" {
  description = "Nombre del cluster de ECS"
  value       = aws_ecs_cluster.principal.name
}

output "servicios_ecs" {
  description = "Servicios de ECS por componente"
  value       = { for k, s in aws_ecs_service.app : k => s.name }
}

output "repositorios_ecr" {
  description = "URL de los repositorios de ECR por componente"
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "vpc_id" {
  value = aws_vpc.principal.id
}
