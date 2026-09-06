locals {
  tags = {
    ManagedBy = "terraform"
    Project   = "node-operator"
    Purpose   = "zero-resource-foundation-network"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "nat" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-hoodi-nat-igw" })
}

resource "aws_subnet" "system" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.system_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  tags = merge(local.tags, {
    Name                                = "${var.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}

resource "aws_subnet" "hoodi" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[0]
  cidr_block              = var.hoodi_subnet_cidrs
  map_public_ip_on_launch = false
  tags = merge(local.tags, {
    Name                                = "${var.name}-hoodi-private"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}

resource "aws_subnet" "nat" {
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[0]
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = false
  tags                    = merge(local.tags, { Name = "${var.name}-hoodi-nat" })
}

resource "aws_eip" "hoodi_nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name}-hoodi-nat" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nat.id
  }
  tags = merge(local.tags, { Name = "${var.name}-nat-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.nat.id
  route_table_id = aws_route_table.public.id
}

resource "aws_nat_gateway" "hoodi" {
  allocation_id     = aws_eip.hoodi_nat.id
  subnet_id         = aws_subnet.nat.id
  connectivity_type = "public"
  depends_on        = [aws_internet_gateway.nat]
  tags              = merge(local.tags, { Name = "${var.name}-hoodi-nat" })
}

resource "aws_route_table" "system" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-system-private" })
}

resource "aws_route_table_association" "system" {
  count          = length(aws_subnet.system)
  subnet_id      = aws_subnet.system[count.index].id
  route_table_id = aws_route_table.system.id
}

resource "aws_route_table" "hoodi" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.hoodi.id
  }
  tags = merge(local.tags, { Name = "${var.name}-private" })
}

resource "aws_route_table_association" "hoodi" {
  subnet_id      = aws_subnet.hoodi.id
  route_table_id = aws_route_table.hoodi.id
}
