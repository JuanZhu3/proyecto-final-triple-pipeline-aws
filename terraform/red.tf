# -----------------------------------------------------------------------------
# RED: VPC con subredes públicas en 2 zonas.
#
# Decisión de costo: las tareas de Fargate van en subredes públicas con IP
# pública (para descargar imágenes de ECR) en lugar de subredes privadas + NAT
# Gateway (~32 USD/mes). El security group de las tareas SOLO acepta tráfico
# que venga del ALB, así que no son accesibles directamente desde Internet.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "disponibles" {
  state = "available"
}

locals {
  zonas = slice(data.aws_availability_zones.disponibles.names, 0, var.numero_zonas)
}

resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.proyecto}-vpc" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.proyecto}-igw" }
}

resource "aws_subnet" "publica" {
  count                   = length(local.zonas)
  vpc_id                  = aws_vpc.principal.id
  availability_zone       = local.zonas[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = false # la IP pública se asigna explícitamente en el servicio ECS
  tags                    = { Name = "${var.proyecto}-publica-${local.zonas[count.index]}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }
  tags = { Name = "${var.proyecto}-rt-publica" }
}

resource "aws_route_table_association" "publica" {
  count          = length(aws_subnet.publica)
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}
