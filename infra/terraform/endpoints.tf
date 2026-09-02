# These endpoints give private managed nodes the AWS control-plane paths needed
# during bootstrap without introducing a NAT gateway or public internet route.
locals {
  required_interface_endpoint_services = toset([
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "eks-auth",
    "kms",
  ])
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name_prefix}-endpoints-"
  description = "HTTPS access to required VPC interface endpoints from managed nodes only."
  vpc_id      = aws_vpc.private.id

  # Security groups are stateful: response traffic for allowed node requests
  # does not need a separate outbound rule. An explicit empty value removes
  # AWS's default allow-all egress rule.
  egress = []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoints"
  })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https_from_nodes" {
  description                  = "HTTPS from managed nodes to VPC interface endpoints"
  security_group_id            = aws_security_group.endpoints.id
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "required_interface" {
  for_each = local.required_interface_endpoint_services

  vpc_id              = aws_vpc.private.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${replace(each.value, ".", "-")}-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.private.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}
