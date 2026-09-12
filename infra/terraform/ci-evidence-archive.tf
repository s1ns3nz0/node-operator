variable "enable_ci_evidence_archive" {
  description = "Create the dedicated immutable S3 archive and GitHub OIDC publisher for redacted CI evidence."
  type        = bool
  default     = true
}

variable "ci_evidence_archive_retention_days" {
  description = "Compliance Object Lock retention for signed CI evidence."
  type        = number
  default     = 365

  validation {
    condition     = var.ci_evidence_archive_retention_days >= 90 && var.ci_evidence_archive_retention_days <= 3650
    error_message = "ci_evidence_archive_retention_days must be between 90 and 3650 days."
  }
}

resource "aws_kms_key" "ci_evidence_archive" {
  count                   = var.enable_ci_evidence_archive ? 1 : 0
  description             = "KMS key for long-term signed CI evidence archive"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.ci_evidence_archive_key[0].json
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ci-evidence-archive"
    Purpose = "signed-ci-evidence-archive"
  })
}

resource "aws_kms_alias" "ci_evidence_archive" {
  count         = var.enable_ci_evidence_archive ? 1 : 0
  name          = "alias/${local.name_prefix}-ci-evidence-archive"
  target_key_id = aws_kms_key.ci_evidence_archive[0].key_id
}

resource "aws_s3_bucket" "ci_evidence_archive" {
  count               = var.enable_ci_evidence_archive ? 1 : 0
  bucket_prefix       = "${local.name_prefix}-ci-evidence-"
  force_destroy       = false
  object_lock_enabled = true
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ci-evidence"
    Purpose = "signed-ci-evidence-archive"
  })
}

resource "aws_s3_bucket_versioning" "ci_evidence_archive" {
  count  = var.enable_ci_evidence_archive ? 1 : 0
  bucket = aws_s3_bucket.ci_evidence_archive[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_object_lock_configuration" "ci_evidence_archive" {
  count  = var.enable_ci_evidence_archive ? 1 : 0
  bucket = aws_s3_bucket.ci_evidence_archive[0].id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.ci_evidence_archive_retention_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ci_evidence_archive" {
  count  = var.enable_ci_evidence_archive ? 1 : 0
  bucket = aws_s3_bucket.ci_evidence_archive[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.ci_evidence_archive[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ci_evidence_archive" {
  count                   = var.enable_ci_evidence_archive ? 1 : 0
  bucket                  = aws_s3_bucket.ci_evidence_archive[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "ci_evidence_archive_key" {
  count                   = var.enable_ci_evidence_archive ? 1 : 0
  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrator.json]

  statement {
    sid    = "AllowCiEvidenceArchiveRoleThroughS3"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github_ci_evidence_archive[0].arn]
    }
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = ["${aws_s3_bucket.ci_evidence_archive[0].arn}/*"]
    }
  }
}

data "aws_iam_policy_document" "github_ci_evidence_archive_assume_role" {
  count = var.enable_ci_evidence_archive ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = [var.github_repository]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.github_oidc_subject_prefix}:environment:ci-evidence-archive"]
    }
  }
}

resource "aws_iam_role" "github_ci_evidence_archive" {
  count              = var.enable_ci_evidence_archive ? 1 : 0
  name               = "${local.name_prefix}-github-ci-evidence-archive"
  assume_role_policy = data.aws_iam_policy_document.github_ci_evidence_archive_assume_role[0].json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "github_ci_evidence_archive" {
  count = var.enable_ci_evidence_archive ? 1 : 0
  statement {
    sid       = "WriteSignedEvidenceOnly"
    actions   = ["s3:AbortMultipartUpload", "s3:PutObject"]
    resources = ["${aws_s3_bucket.ci_evidence_archive[0].arn}/ci/*"]
  }
  statement {
    sid       = "ListEvidencePrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ci_evidence_archive[0].arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["ci/*"]
    }
  }
  statement {
    sid       = "VerifyAfterWrite"
    actions   = ["s3:GetObject", "s3:HeadObject"]
    resources = ["${aws_s3_bucket.ci_evidence_archive[0].arn}/ci/*"]
  }
}

resource "aws_iam_role_policy" "github_ci_evidence_archive" {
  count  = var.enable_ci_evidence_archive ? 1 : 0
  name   = "${local.name_prefix}-github-ci-evidence-archive"
  role   = aws_iam_role.github_ci_evidence_archive[0].id
  policy = data.aws_iam_policy_document.github_ci_evidence_archive[0].json
}

data "aws_iam_policy_document" "ci_evidence_archive" {
  count = var.enable_ci_evidence_archive ? 1 : 0
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.ci_evidence_archive[0].arn, "${aws_s3_bucket.ci_evidence_archive[0].arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "ci_evidence_archive" {
  count  = var.enable_ci_evidence_archive ? 1 : 0
  bucket = aws_s3_bucket.ci_evidence_archive[0].id
  policy = data.aws_iam_policy_document.ci_evidence_archive[0].json
}

resource "aws_s3_bucket_notification" "ci_evidence_archive" {
  count       = var.enable_ci_evidence_archive ? 1 : 0
  bucket      = aws_s3_bucket.ci_evidence_archive[0].id
  eventbridge = true
}

output "ci_evidence_archive_bucket_name" {
  description = "Immutable S3 bucket for redacted, Cosign-signed CI evidence."
  value       = try(aws_s3_bucket.ci_evidence_archive[0].id, null)
}

output "ci_evidence_archive_role_arn" {
  description = "GitHub OIDC role that can write only the signed CI evidence prefix."
  value       = try(aws_iam_role.github_ci_evidence_archive[0].arn, null)
}
