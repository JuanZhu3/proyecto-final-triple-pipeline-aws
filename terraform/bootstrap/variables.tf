variable "region" {
  description = "Región seleccionada del proyecto AWS (AWS Settings > View all projects > Overview > Additional Info > Region)"
  type        = string
  default     = "us-east-2"
}

variable "proyecto" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "proyecto-final"
}
