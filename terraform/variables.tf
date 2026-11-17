variable "region" {
  description = "Región seleccionada del proyecto AWS"
  type        = string
  default     = "us-east-2"
}

variable "proyecto" {
  description = "Prefijo para nombrar todos los recursos"
  type        = string
  default     = "proyecto-final"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "numero_zonas" {
  description = "Zonas de disponibilidad a usar (el ALB exige al menos 2)"
  type        = number
  default     = 2
  validation {
    condition     = var.numero_zonas >= 2 && var.numero_zonas <= 3
    error_message = "Use entre 2 y 3 zonas de disponibilidad."
  }
}

variable "servicios" {
  description = "Definición de los dos servicios de ECS (frontend y backend)"
  type = map(object({
    puerto       = number
    cpu          = number
    memoria      = number
    ruta_health  = string
    patrones_alb = list(string) # rutas que el ALB envía a este servicio ([] = regla por defecto)
    prioridad    = number
  }))
  default = {
    frontend = {
      puerto       = 8080
      cpu          = 256
      memoria      = 512
      ruta_health  = "/health"
      patrones_alb = []
      prioridad    = 0
    }
    backend = {
      puerto       = 3000
      cpu          = 256
      memoria      = 512
      ruta_health  = "/api/health"
      patrones_alb = ["/api/*"]
      prioridad    = 10
    }
  }
}

variable "retencion_logs_dias" {
  description = "Días de retención de los logs de CloudWatch"
  type        = number
  default     = 7
}

variable "imagenes_a_conservar" {
  description = "Número de imágenes que conserva la política de ciclo de vida de ECR"
  type        = number
  default     = 10
}
