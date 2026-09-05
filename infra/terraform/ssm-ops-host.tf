# This host is a short-lived TCP tunnel target for Session Manager. It has no
# public IP, inbound rule, SSH key, Kubernetes client, or persistent credential.
# The operator's local AWS identity remains responsible for EKS authentication.
data "aws_ssm_parameter" "al2023_x86_64" {
  count = var.enable_temporary_ssm_ops_host ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "temporary_ssm_ops_host_assume_role" {
  count = var.enable_temporary_ssm_ops_host ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "temporary_ssm_ops_host" {
  count              = var.enable_temporary_ssm_ops_host ? 1 : 0
  name               = "${local.name_prefix}-temporary-ssm-ops-host"
  assume_role_policy = data.aws_iam_policy_document.temporary_ssm_ops_host_assume_role[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-temporary-ssm-ops-host"
    Purpose = "temporary-private-eks-tunnel"
    }, var.temporary_ssm_ops_host_termination_at == "" ? {} : {
    ExpiresAt = var.temporary_ssm_ops_host_termination_at
  })
}

resource "aws_iam_role_policy_attachment" "temporary_ssm_ops_host" {
  count      = var.enable_temporary_ssm_ops_host ? 1 : 0
  role       = aws_iam_role.temporary_ssm_ops_host[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "temporary_ssm_ops_host" {
  count = var.enable_temporary_ssm_ops_host ? 1 : 0
  name  = "${local.name_prefix}-temporary-ssm-ops-host"
  role  = aws_iam_role.temporary_ssm_ops_host[0].name
}

resource "aws_security_group" "temporary_ssm_ops_host" {
  count       = var.enable_temporary_ssm_ops_host ? 1 : 0
  name_prefix = "${local.name_prefix}-temporary-ssm-ops-host-"
  description = "No-ingress security group for the temporary SSM tunnel host."
  vpc_id      = aws_vpc.private.id

  ingress = []

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-temporary-ssm-ops-host"
    Purpose = "temporary-private-eks-tunnel"
    }, var.temporary_ssm_ops_host_termination_at == "" ? {} : {
    ExpiresAt = var.temporary_ssm_ops_host_termination_at
  })
}

resource "aws_vpc_security_group_egress_rule" "temporary_ssm_ops_host_to_endpoints" {
  count                        = var.enable_temporary_ssm_ops_host ? 1 : 0
  description                  = "HTTPS from temporary SSM tunnel host to private interface endpoints"
  security_group_id            = aws_security_group.temporary_ssm_ops_host[0].id
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "temporary_ssm_ops_host_to_cluster" {
  count                        = var.enable_temporary_ssm_ops_host ? 1 : 0
  description                  = "HTTPS TCP tunnel from temporary SSM host to private EKS API"
  security_group_id            = aws_security_group.temporary_ssm_ops_host[0].id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_temporary_ssm_ops_host" {
  count                        = var.enable_temporary_ssm_ops_host ? 1 : 0
  description                  = "Kubernetes API TCP tunnel from temporary SSM operations host"
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.temporary_ssm_ops_host[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_instance" "temporary_ssm_ops_host" {
  count                       = var.enable_temporary_ssm_ops_host ? 1 : 0
  ami                         = data.aws_ssm_parameter.al2023_x86_64[0].value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.temporary_ssm_ops_host[0].name
  vpc_security_group_ids      = [aws_security_group.temporary_ssm_ops_host[0].id]

  # A local shutdown cannot leave a stopped administration host behind.
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

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-temporary-ssm-ops-host"
    Purpose = "temporary-private-eks-tunnel"
    }, var.temporary_ssm_ops_host_termination_at == "" ? {} : {
    ExpiresAt = var.temporary_ssm_ops_host_termination_at
  })

  depends_on = [
    aws_iam_role_policy_attachment.temporary_ssm_ops_host,
    aws_vpc_endpoint.required_interface,
  ]
}

data "aws_iam_policy_document" "temporary_ssm_ops_host_stop_assume_role" {
  count = var.enable_temporary_ssm_ops_host && var.temporary_ssm_ops_host_termination_at != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      # Scheduler supplies its schedule-group ARN when it assumes an execution
      # role; pinning this to the default group preserves confused-deputy
      # protection without making CreateSchedule's role validation impossible.
      values = ["arn:aws:scheduler:${var.aws_region}:${var.aws_account_id}:schedule-group/default"]
    }
  }
}

resource "aws_iam_role" "temporary_ssm_ops_host_stop" {
  count              = var.enable_temporary_ssm_ops_host && var.temporary_ssm_ops_host_termination_at != "" ? 1 : 0
  name               = "${local.name_prefix}-temporary-ssm-ops-host-stop"
  assume_role_policy = data.aws_iam_policy_document.temporary_ssm_ops_host_stop_assume_role[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-temporary-ssm-ops-host-stop"
    Purpose = "one-time-temporary-ops-host-stop"
    }, {
    ExpiresAt = var.temporary_ssm_ops_host_termination_at
  })
}

data "aws_iam_policy_document" "temporary_ssm_ops_host_stop" {
  count = var.enable_temporary_ssm_ops_host && var.temporary_ssm_ops_host_termination_at != "" ? 1 : 0

  statement {
    sid       = "TerminateOnlyTheTemporaryOpsHost"
    actions   = ["ec2:TerminateInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/${aws_instance.temporary_ssm_ops_host[0].id}"]
  }
}

resource "aws_iam_role_policy" "temporary_ssm_ops_host_stop" {
  count  = var.enable_temporary_ssm_ops_host && var.temporary_ssm_ops_host_termination_at != "" ? 1 : 0
  name   = "${local.name_prefix}-temporary-ssm-ops-host-stop"
  role   = aws_iam_role.temporary_ssm_ops_host_stop[0].id
  policy = data.aws_iam_policy_document.temporary_ssm_ops_host_stop[0].json
}

resource "aws_scheduler_schedule" "temporary_ssm_ops_host_stop" {
  count                        = var.enable_temporary_ssm_ops_host && var.temporary_ssm_ops_host_termination_at != "" ? 1 : 0
  name                         = "${local.name_prefix}-temporary-ssm-ops-host-stop"
  description                  = "One-time termination of the temporary SSM operations host."
  schedule_expression          = "at(${var.temporary_ssm_ops_host_termination_at})"
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:terminateInstances"
    role_arn = aws_iam_role.temporary_ssm_ops_host_stop[0].arn
    input = jsonencode({
      InstanceIds = [aws_instance.temporary_ssm_ops_host[0].id]
    })
  }

  depends_on = [aws_iam_role_policy.temporary_ssm_ops_host_stop]
}
