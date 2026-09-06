terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers { aws = { source = "hashicorp/aws", version = ">= 5.31.0, < 6.0.0" } }
}

provider "aws" { region = var.aws_region }

data "aws_ssm_parameter" "al2023" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }

resource "aws_security_group" "host" {
  name_prefix = "${var.name}-ops-access-"
  description = "No-ingress temporary private EKS operations host."
  vpc_id      = var.vpc_id
  ingress     = []
  tags        = { ManagedBy = "terraform", Project = "node-operator", Purpose = "ops-access" }
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name}-ops-access-endpoints-"
  description = "Private Session Manager endpoints for the temporary operations host."
  vpc_id      = var.vpc_id
  egress      = []
  tags        = { ManagedBy = "terraform", Project = "node-operator", Purpose = "ops-access" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints" {
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.host.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_endpoints" {
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_cluster" {
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = var.cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cluster" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.host.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(["ssm", "ssmmessages", "ec2messages"])
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.endpoints.id]
}

resource "aws_iam_role" "host" {
  name               = "${var.name}-ops-access"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  name = "${var.name}-ops-access"
  role = aws_iam_role.host.name
}

resource "aws_instance" "host" {
  ami                                  = data.aws_ssm_parameter.al2023.value
  instance_type                        = "t3.micro"
  subnet_id                            = var.subnet_id
  associate_public_ip_address          = false
  iam_instance_profile                 = aws_iam_instance_profile.host.name
  vpc_security_group_ids               = [aws_security_group.host.id]
  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }
  tags       = { ManagedBy = "terraform", Project = "node-operator", Purpose = "ops-access" }
  depends_on = [aws_iam_role_policy_attachment.ssm, aws_vpc_endpoint.ssm]
}

output "instance_id" { value = aws_instance.host.id }
