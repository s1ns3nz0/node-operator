resource "aws_vpc" "private" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# The default security group cannot be removed. Explicitly manage it as deny-all
# so resources must opt into the dedicated security groups declared below.
resource "aws_default_security_group" "private" {
  vpc_id = aws_vpc.private.id

  ingress = []
  egress  = []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-deny"
  })
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.audit.arn

  tags = local.common_tags
}

data "aws_iam_policy_document" "vpc_flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${local.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "vpc_flow_logs" {
  statement {
    sid       = "WriteOnlyVpcFlowLogGroup"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "${local.name_prefix}-vpc-flow-logs"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.vpc_flow_logs.json
}

resource "aws_flow_log" "private" {
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.private.id

  depends_on = [aws_iam_role_policy.vpc_flow_logs]

  tags = local.common_tags
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.private.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = var.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                = "${local.name_prefix}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}

# Deliberately no Internet gateway, NAT gateway, or public route is defined.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.private.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "cluster" {
  name_prefix = "${local.name_prefix}-cluster-"
  description = "Private EKS control-plane access only from baseline nodes."
  vpc_id      = aws_vpc.private.id

  egress {
    description = "Control-plane traffic within the private VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_security_group" "nodes" {
  name_prefix = "${local.name_prefix}-nodes-"
  description = "Private managed-node communication; no internet ingress."
  vpc_id      = aws_vpc.private.id

  egress {
    description = "Private VPC service traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nodes"
  })
}

# Keep all ingress rules separate from their groups. Inline mutual references
# would create a Terraform dependency cycle even though the network intent is
# valid, and mixing inline with standalone rules creates conflicting ownership.
resource "aws_vpc_security_group_ingress_rule" "nodes_self_all" {
  description                  = "Node-to-node Kubernetes traffic"
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_nodes" {
  description                  = "Kubernetes API from managed nodes"
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_kubelet_from_cluster" {
  description                  = "Kubelet API from the control plane"
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_webhook_from_cluster" {
  description                  = "Webhook and extension API traffic from the control plane"
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
