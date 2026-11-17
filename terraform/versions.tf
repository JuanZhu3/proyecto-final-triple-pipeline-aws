terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Estado remoto en S3 con bloqueo nativo (use_lockfile, sin DynamoDB).
  # bucket/key/region se pasan en `terraform init -backend-config=backend.hcl`
  # (ver backend.hcl.example) para no fijar el ID de cuenta en el código.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Proyecto  = var.proyecto
      ManagedBy = "terraform"
    }
  }
}
