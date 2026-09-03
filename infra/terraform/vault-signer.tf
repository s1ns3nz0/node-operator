variable "vault_signer_endpoint" {
  description = "Private Vault Transit signer endpoint; never a public URL."
  type        = string
  default     = ""
  validation {
    condition     = var.vault_signer_endpoint == "" || can(regex("^https://", var.vault_signer_endpoint))
    error_message = "vault_signer_endpoint must be HTTPS when configured."
  }
}

variable "enable_release_signer" {
  description = "Enable the private CodeBuild release signer only after plan review."
  type        = bool
  default     = false
}

variable "release_signer_subnet_ids" {
  description = "Private subnet IDs for the release signer CodeBuild project."
  type        = list(string)
  default     = []
}

resource "aws_security_group" "release_signer" {
  count       = var.enable_release_signer ? 1 : 0
  name_prefix = "${local.name_prefix}-signer-"
  description = "Private release signer egress to approved VPC services only."
  vpc_id      = aws_vpc.private.id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS to private Vault and service endpoints"
  }
  tags = local.common_tags
}

variable "github_repository" {
  description = "GitHub repository allowed to start the release signer, owner/name."
  type        = string
  default     = "s1ns3nz0/node-operator"
}

variable "release_artifact_bucket_arn" {
  description = "Dedicated release artifact bucket ARN; empty keeps signer disabled."
  type        = string
  default     = ""
}

resource "aws_s3_bucket" "release_artifacts" {
  count               = var.enable_release_signer ? 1 : 0
  bucket_prefix       = "${local.name_prefix}-release-"
  force_destroy       = false
  object_lock_enabled = true
  tags                = local.common_tags
}

data "aws_iam_policy_document" "release_artifacts" {
  count = var.enable_release_signer ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.release_artifacts[0].arn, "${aws_s3_bucket.release_artifacts[0].arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id
  policy = data.aws_iam_policy_document.release_artifacts[0].json
}

resource "aws_s3_bucket_public_access_block" "release_artifacts" {
  count                   = var.enable_release_signer ? 1 : 0
  bucket                  = aws_s3_bucket.release_artifacts[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudwatch_log_group" "release_signer" {
  count             = var.enable_release_signer ? 1 : 0
  name              = "/aws/codebuild/${local.name_prefix}-release-signer"
  retention_in_days = 90
  tags              = local.common_tags
}

resource "aws_iam_role" "github_release_runner" {
  count = var.enable_release_signer ? 1 : 0
  name  = "${local.name_prefix}-github-release-runner"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/tags/v*" }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_release_runner" {
  count  = var.enable_release_signer ? 1 : 0
  role   = aws_iam_role.github_release_runner[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = aws_codebuild_project.release_signer[0].arn }] })
}

resource "aws_iam_role" "release_codebuild_signer" {
  count              = var.enable_release_signer ? 1 : 0
  name               = "${local.name_prefix}-release-signer"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = local.common_tags
}

data "aws_iam_policy_document" "release_codebuild_signer" {
  count = var.enable_release_signer ? 1 : 0

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.release_signer[0].arn}:*"]
  }
  dynamic "statement" {
    for_each = var.release_artifact_bucket_arn == "" ? [] : [var.release_artifact_bucket_arn]
    content {
      sid       = "ReleaseArtifacts"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["${statement.value}/release/*"]
    }
  }
  dynamic "statement" {
    for_each = var.enable_release_signer ? [1] : []
    content {
      sid       = "ReleaseBucketPrefixes"
      actions   = ["s3:GetObject", "s3:PutObject"]
      resources = ["${aws_s3_bucket.release_artifacts[0].arn}/release-input/*", "${aws_s3_bucket.release_artifacts[0].arn}/release-output/*"]
    }
  }
}

resource "aws_iam_role_policy" "release_codebuild_signer" {
  count  = var.enable_release_signer ? 1 : 0
  role   = aws_iam_role.release_codebuild_signer[0].id
  policy = data.aws_iam_policy_document.release_codebuild_signer[0].json
}

resource "aws_codebuild_project" "release_signer" {
  count         = var.enable_release_signer ? 1 : 0
  name          = "${local.name_prefix}-release-signer"
  service_role  = aws_iam_role.release_codebuild_signer[0].arn
  build_timeout = 30
  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.release_artifacts[0].id
    packaging = "NONE"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }
  vpc_config {
    vpc_id             = aws_vpc.private.id
    subnets            = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.release_signer[0].id]
  }
  source {
    type     = "S3"
    location = "${aws_s3_bucket.release_artifacts[0].id}/release-input/bootstrap.zip"
  }
  tags = local.common_tags
}
