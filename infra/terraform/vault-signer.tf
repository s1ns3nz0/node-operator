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

# Release artifacts and CodeBuild logs have separate keys so a signer role
# cannot use its artifact key to read or write operational log data. The
# dedicated KMS administrator role remains the break-glass administrator; the
# account root principal does not receive direct kms:* access.
data "aws_iam_policy_document" "release_artifacts_key" {
  count = var.enable_release_signer ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrator.json]

  statement {
    sid    = "AllowReleaseSignerToUseArtifactKeyOnlyThroughS3"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.release_codebuild_signer[0].arn]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${aws_s3_bucket.release_artifacts[0].arn}/*"]
    }
  }

  statement {
    sid    = "AllowArtifactReplicationRoleToDecryptOnlyThroughSourceS3"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.release_artifact_replication[0].arn]
    }

    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "release_artifacts" {
  count                   = var.enable_release_signer ? 1 : 0
  description             = "Release signer artifact encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.release_artifacts_key[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-release-artifacts"
    Purpose = "release-artifact-encryption"
  })
}

resource "aws_kms_alias" "release_artifacts" {
  count         = var.enable_release_signer ? 1 : 0
  name          = "alias/${local.name_prefix}-release-artifacts"
  target_key_id = aws_kms_key.release_artifacts[0].key_id
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

resource "aws_s3_bucket_lifecycle_configuration" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id

  rule {
    id     = "retain-releases-and-expire-stale-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# EventBridge is the approved in-account event integration point. Consumers
# (for example, a SIEM forwarding rule) are intentionally not created here;
# their destination and retention need an independent approval.
resource "aws_s3_bucket_notification" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id

  eventbridge = true
}

resource "aws_s3_bucket_object_lock_configuration" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.release_artifacts[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "release_signer_logs_key" {
  count = var.enable_release_signer ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrator.json]

  statement {
    sid    = "AllowCloudWatchLogsToUseReleaseSignerLogKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions   = ["kms:Decrypt*", "kms:Describe*", "kms:Encrypt*", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/${local.name_prefix}-release-signer"]
    }
  }
}

resource "aws_kms_key" "release_signer_logs" {
  count                   = var.enable_release_signer ? 1 : 0
  description             = "Release signer CodeBuild log encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.release_signer_logs_key[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-release-signer-logs"
    Purpose = "release-signer-log-encryption"
  })
}

resource "aws_kms_alias" "release_signer_logs" {
  count         = var.enable_release_signer ? 1 : 0
  name          = "alias/${local.name_prefix}-release-signer-logs"
  target_key_id = aws_kms_key.release_signer_logs[0].key_id
}

resource "aws_s3_bucket" "release_artifacts_replica" {
  count         = var.enable_release_signer ? 1 : 0
  provider      = aws.audit_replica
  bucket_prefix = "${local.name_prefix}-release-dr-"
  force_destroy = false

  object_lock_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-release-dr"
    Purpose = "release-artifact-disaster-recovery"
  })
}

resource "aws_s3_bucket_public_access_block" "release_artifacts_replica" {
  count                   = var.enable_release_signer ? 1 : 0
  provider                = aws.audit_replica
  bucket                  = aws_s3_bucket.release_artifacts_replica[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  versioning_configuration { status = "Enabled" }
}

data "aws_iam_policy_document" "release_artifacts_replica_key" {
  count = var.enable_release_signer ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrator.json]

  statement {
    sid    = "AllowArtifactReplicationRoleToEncryptOnlyThroughReplicaS3"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.release_artifact_replication[0].arn]
    }

    actions   = ["kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.audit_replica_region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "release_artifacts_replica" {
  count                   = var.enable_release_signer ? 1 : 0
  provider                = aws.audit_replica
  description             = "Tokyo disaster-recovery encryption key for release signer artifacts"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.release_artifacts_replica_key[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-release-dr"
    Purpose = "release-artifact-disaster-recovery-encryption"
  })
}

resource "aws_kms_alias" "release_artifacts_replica" {
  count         = var.enable_release_signer ? 1 : 0
  provider      = aws.audit_replica
  name          = "alias/${local.name_prefix}-release-artifacts-dr"
  target_key_id = aws_kms_key.release_artifacts_replica[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.release_artifacts_replica[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  rule {
    id     = "retain-replicated-releases-and-expire-stale-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  eventbridge = true
}

resource "aws_s3_bucket_object_lock_configuration" "release_artifacts_replica" {
  count    = var.enable_release_signer ? 1 : 0
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.release_artifacts_replica[0].id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 30
    }
  }
}

resource "aws_cloudwatch_log_group" "release_signer" {
  count             = var.enable_release_signer ? 1 : 0
  name              = "/aws/codebuild/${local.name_prefix}-release-signer"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.release_signer_logs[0].arn
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
  statement {
    sid = "UseOnlyReleaseArtifactEncryptionKeyThroughS3"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
    ]
    resources = [aws_kms_key.release_artifacts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "release_codebuild_signer" {
  count  = var.enable_release_signer ? 1 : 0
  role   = aws_iam_role.release_codebuild_signer[0].id
  policy = data.aws_iam_policy_document.release_codebuild_signer[0].json
}

data "aws_iam_policy_document" "release_artifact_replication_assume_role" {
  count = var.enable_release_signer ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "release_artifact_replication" {
  count              = var.enable_release_signer ? 1 : 0
  name               = "${local.name_prefix}-release-artifact-replication"
  assume_role_policy = data.aws_iam_policy_document.release_artifact_replication_assume_role[0].json

  tags = local.common_tags
}

data "aws_iam_policy_document" "release_artifact_replication" {
  count = var.enable_release_signer ? 1 : 0

  statement {
    sid = "ReadOnlyReleaseArtifactSourceVersions"
    actions = [
      "s3:GetObjectLegalHold",
      "s3:GetObjectRetention",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionTagging",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.release_artifacts[0].arn, "${aws_s3_bucket.release_artifacts[0].arn}/*"]
  }

  statement {
    sid       = "WriteOnlyReleaseArtifactReplicaVersions"
    actions   = ["s3:ObjectOwnerOverrideToBucketOwner", "s3:ReplicateDelete", "s3:ReplicateObject", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.release_artifacts_replica[0].arn}/*"]
  }

  statement {
    sid       = "UseOnlyApprovedReleaseArtifactKeys"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.release_artifacts[0].arn]
  }

  statement {
    sid       = "EncryptOnlyWithReleaseArtifactReplicaKey"
    actions   = ["kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.release_artifacts_replica[0].arn]
  }
}

resource "aws_iam_role_policy" "release_artifact_replication" {
  count  = var.enable_release_signer ? 1 : 0
  name   = "${local.name_prefix}-release-artifact-replication"
  role   = aws_iam_role.release_artifact_replication[0].id
  policy = data.aws_iam_policy_document.release_artifact_replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "release_artifacts" {
  count  = var.enable_release_signer ? 1 : 0
  bucket = aws_s3_bucket.release_artifacts[0].id
  role   = aws_iam_role.release_artifact_replication[0].arn

  rule {
    id     = "replicate-release-artifacts-to-tokyo"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.release_artifacts_replica[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.release_artifacts_replica[0].arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.release_artifacts,
    aws_s3_bucket_versioning.release_artifacts_replica,
    aws_iam_role_policy.release_artifact_replication,
  ]
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
