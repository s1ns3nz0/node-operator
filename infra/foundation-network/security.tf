data "aws_caller_identity" "foundation" {}

resource "aws_default_security_group" "foundation" {
  vpc_id  = aws_vpc.this.id
  ingress = []
  egress  = []
  tags    = merge(local.tags, { Name = "${var.name}-foundation-default-deny" })
}

resource "aws_kms_key" "foundation_flow_logs" {
  description             = "Private foundation VPC flow log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountIamAdministration", Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.foundation.account_id}:root" }
        Action    = "kms:*", Resource = "*"
      },
      {
        Sid       = "EncryptOnlyFoundationFlowLogs", Effect = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.foundation.account_id}:log-group:/aws/vpc/${var.name}/foundation-flow-logs" } }
      }
    ]
  })
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "foundation_flow_logs" {
  name              = "/aws/vpc/${var.name}/foundation-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.foundation_flow_logs.arn
  tags              = local.tags
}

resource "aws_iam_role" "foundation_flow_logs" {
  name = "${var.name}-foundation-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.foundation.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.foundation.account_id}:vpc-flow-log/*" }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "foundation_flow_logs" {
  role = aws_iam_role.foundation_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.foundation_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "foundation" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.foundation_flow_logs.arn
  iam_role_arn         = aws_iam_role.foundation_flow_logs.arn
  depends_on           = [aws_iam_role_policy.foundation_flow_logs]
  tags                 = local.tags
}
