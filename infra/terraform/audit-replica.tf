# The audit replica is intentionally in Tokyo, not in the primary Seoul Region.
# It is a recovery copy only: lifecycle rules retain delete markers and the
# replication role cannot delete either source or destination records.
resource "aws_s3_bucket" "audit_replica" {
  provider      = aws.audit_replica
  bucket_prefix = "${local.name_prefix}-audit-dr-"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-audit-dr"
    Purpose = "audit-disaster-recovery"
  })
}

resource "aws_s3_bucket_public_access_block" "audit_replica" {
  provider                = aws.audit_replica
  bucket                  = aws_s3_bucket.audit_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "audit_replica" {
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.audit_replica.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "audit_replica" {
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.audit_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "audit_replica_key" {
  statement {
    sid    = "AllowDedicatedKMSAdministrator"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.kms_administrator.arn]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAuditReplicationRoleToEncryptReplicaObjects"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.audit_replication.arn]
    }

    actions   = ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.audit_replica_region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "audit_replica" {
  provider                = aws.audit_replica
  description             = "Tokyo disaster-recovery encryption key for replicated audit logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.audit_replica_key.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-audit-dr"
  })
}

resource "aws_kms_alias" "audit_replica" {
  provider      = aws.audit_replica
  name          = "alias/${local.name_prefix}-audit-dr"
  target_key_id = aws_kms_key.audit_replica.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_replica" {
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.audit_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.audit_replica.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_replica" {
  provider = aws.audit_replica
  bucket   = aws_s3_bucket.audit_replica.id

  rule {
    id     = "retain-replicated-audit-records"
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

data "aws_iam_policy_document" "audit_replication_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "audit_replication" {
  name               = "${local.name_prefix}-audit-replication"
  assume_role_policy = data.aws_iam_policy_document.audit_replication_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "audit_replication" {
  statement {
    sid       = "ReadOnlyAuditSourceVersions"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket", "s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = [aws_s3_bucket.audit.arn, "${aws_s3_bucket.audit.arn}/*"]
  }

  statement {
    sid       = "WriteOnlyAuditReplicaVersions"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"]
    resources = ["${aws_s3_bucket.audit_replica.arn}/*"]
  }

  statement {
    sid       = "UseOnlyApprovedAuditKeysForReplication"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.audit.arn]
  }

  statement {
    sid       = "EncryptOnlyWithAuditReplicaKey"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.audit_replica.arn]
  }
}

resource "aws_iam_role_policy" "audit_replication" {
  name   = "${local.name_prefix}-audit-replication"
  role   = aws_iam_role.audit_replication.id
  policy = data.aws_iam_policy_document.audit_replication.json
}

resource "aws_s3_bucket_replication_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  role   = aws_iam_role.audit_replication.arn

  rule {
    id     = "replicate-audit-records-to-tokyo"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.audit_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.audit_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.audit,
    aws_s3_bucket_versioning.audit_replica,
    aws_iam_role_policy.audit_replication,
  ]
}
