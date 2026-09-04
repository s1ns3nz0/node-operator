# This host is deliberately a short-lived SSM tunnel endpoint, not a bastion.
# It has no public IP, inbound rule, SSH key, user data, Kubernetes config, or
# application secret material. A human's existing EKS identity remains the only
# identity that can authenticate kubectl through an SSM port-forward.

locals {
  ssm_ops_host_endpoint_services = toset([
    "ssm",
    "ssmmessages",
    "ec2messages",
  ])
}

# AWS maintains this public parameter as the current Amazon Linux 2023 image.
# Resolving it only when the host is enabled prevents an unrelated baseline plan
# from depending on Parameter Store. It deliberately avoids an unpinned AMI ID
# copied into configuration or any bootstrap download script.
data "aws_ssm_parameter" "al2023_ssm_ops_host_ami" {
  count = var.enable_ssm_ops_host ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "ssm_ops_host" {
  count       = var.enable_ssm_ops_host ? 1 : 0
  name_prefix = "${local.name_prefix}-ssm-ops-host-"
  description = "No-ingress temporary SSM tunnel host; HTTPS only to its endpoints and the private EKS API."
  vpc_id      = aws_vpc.private.id
  egress      = []

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ssm-ops-host"
    Purpose = "temporary-ssm-tunnel"
  })
}

resource "aws_security_group" "ssm_ops_host_endpoints" {
  count       = var.enable_ssm_ops_host ? 1 : 0
  name_prefix = "${local.name_prefix}-ssm-ops-endpoints-"
  description = "Private SSM interface endpoints reachable only from the temporary SSM tunnel host."
  vpc_id      = aws_vpc.private.id
  egress      = []

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ssm-ops-endpoints"
    Purpose = "temporary-ssm-tunnel"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssm_ops_host_endpoints_https" {
  count                        = var.enable_ssm_ops_host ? 1 : 0
  description                  = "HTTPS from the temporary SSM tunnel host only"
  security_group_id            = aws_security_group.ssm_ops_host_endpoints[0].id
  referenced_security_group_id = aws_security_group.ssm_ops_host[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ssm_ops_host_to_endpoints_https" {
  count                        = var.enable_ssm_ops_host ? 1 : 0
  description                  = "HTTPS to the dedicated private SSM interface endpoints"
  security_group_id            = aws_security_group.ssm_ops_host[0].id
  referenced_security_group_id = aws_security_group.ssm_ops_host_endpoints[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ssm_ops_host_to_cluster_https" {
  count                        = var.enable_ssm_ops_host ? 1 : 0
  description                  = "HTTPS to the private EKS API only"
  security_group_id            = aws_security_group.ssm_ops_host[0].id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_ssm_ops_host" {
  count                        = var.enable_ssm_ops_host ? 1 : 0
  description                  = "Kubernetes API through the temporary SSM tunnel host"
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.ssm_ops_host[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# These are intentionally separate from the baseline endpoint security group:
# the latter also permits nodes and build runners, whereas this group permits
# only the temporary host. No public endpoint, NAT, or internet route is added.
resource "aws_vpc_endpoint" "ssm_ops_host" {
  for_each = var.enable_ssm_ops_host ? local.ssm_ops_host_endpoint_services : toset([])

  vpc_id              = aws_vpc.private.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.ssm_ops_host_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ssm-ops-${each.value}-endpoint"
    Purpose = "temporary-ssm-tunnel"
  })
}

data "aws_iam_policy_document" "ssm_ops_host_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_ops_host" {
  count              = var.enable_ssm_ops_host ? 1 : 0
  name               = "${local.name_prefix}-ssm-ops-host"
  assume_role_policy = data.aws_iam_policy_document.ssm_ops_host_assume_role.json

  tags = merge(local.common_tags, {
    Purpose = "temporary-ssm-tunnel"
  })
}

# AWS-managed AmazonSSMManagedInstanceCore is the narrowly intended policy for
# a Session Manager managed instance. No EKS, S3, Secrets Manager, or IAM API
# permissions are added to the instance role.
resource "aws_iam_role_policy_attachment" "ssm_ops_host_core" {
  count      = var.enable_ssm_ops_host ? 1 : 0
  role       = aws_iam_role.ssm_ops_host[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_ops_host" {
  count = var.enable_ssm_ops_host ? 1 : 0
  name  = "${local.name_prefix}-ssm-ops-host"
  role  = aws_iam_role.ssm_ops_host[0].name
}

resource "aws_instance" "ssm_ops_host" {
  count                       = var.enable_ssm_ops_host ? 1 : 0
  ami                         = data.aws_ssm_parameter.al2023_ssm_ops_host_ami[0].value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ssm_ops_host[0].id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_ops_host[0].name
  associate_public_ip_address = false

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn
    volume_size           = 20
    volume_type           = "gp3"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ssm-ops-host"
    Purpose = "temporary-ssm-tunnel"
  })

  depends_on = [
    aws_iam_role_policy_attachment.ssm_ops_host_core,
    aws_vpc_endpoint.ssm_ops_host,
  ]
}

# A one-time EventBridge Scheduler `at()` expression is the reliable AWS-native
# mechanism for an explicit expiry. We intentionally do not derive “today” via
# timestamp(): an old saved plan could otherwise create a missed or incorrect
# schedule. Set the exact future KST wall-clock time at apply, for example
# ssm_ops_host_termination_at=2026-09-04T22:00:00.
data "aws_iam_policy_document" "ssm_ops_host_termination_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_ops_host_termination" {
  count              = var.enable_ssm_ops_host && var.ssm_ops_host_termination_at != "" ? 1 : 0
  name               = "${local.name_prefix}-ssm-ops-host-termination"
  assume_role_policy = data.aws_iam_policy_document.ssm_ops_host_termination_assume_role.json

  tags = merge(local.common_tags, {
    Purpose = "temporary-ssm-tunnel-termination"
  })
}

data "aws_iam_policy_document" "ssm_ops_host_termination" {
  count = var.enable_ssm_ops_host && var.ssm_ops_host_termination_at != "" ? 1 : 0

  statement {
    sid       = "TerminateOnlyTemporarySsmOpsHost"
    actions   = ["ec2:TerminateInstances"]
    resources = [aws_instance.ssm_ops_host[0].arn]
  }
}

resource "aws_iam_role_policy" "ssm_ops_host_termination" {
  count  = var.enable_ssm_ops_host && var.ssm_ops_host_termination_at != "" ? 1 : 0
  name   = "${local.name_prefix}-ssm-ops-host-termination"
  role   = aws_iam_role.ssm_ops_host_termination[0].id
  policy = data.aws_iam_policy_document.ssm_ops_host_termination[0].json
}

resource "aws_scheduler_schedule" "ssm_ops_host_termination" {
  count                         = var.enable_ssm_ops_host && var.ssm_ops_host_termination_at != "" ? 1 : 0
  name                          = "${local.name_prefix}-ssm-ops-host-termination"
  description                   = "One-time termination of the temporary private SSM tunnel host."
  schedule_expression           = "at(${var.ssm_ops_host_termination_at})"
  schedule_expression_timezone  = "Asia/Seoul"
  state                         = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:terminateInstances"
    role_arn = aws_iam_role.ssm_ops_host_termination[0].arn
    input    = jsonencode({ InstanceIds = [aws_instance.ssm_ops_host[0].id] })
  }

  depends_on = [aws_iam_role_policy.ssm_ops_host_termination]
}
