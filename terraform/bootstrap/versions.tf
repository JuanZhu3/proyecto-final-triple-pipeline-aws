terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Estado LOCAL a propósito: este módulo crea el bucket del estado remoto.
  # terraform.tfstate está excluido en .gitignore.
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Proyecto   = var.proyecto
      ManagedBy  = "terraform"
      Componente = "bootstrap"
    }
  }
}
