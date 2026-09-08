# Firehose validates these caller permissions on PutRecord/PutRecordBatch.
# A separate CMK prevents buffer encryption from widening access to the archive.
data "aws_iam_policy_document" "validator_firehose_buffer" {
  source_policy_documents = [data.aws_iam_policy_document.kms_key_administrator.json]
  statement {
    sid = "AllowOnlyCloudWatchSubscriptionProducer"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.validator_cloudwatch_subscription.arn]
    }
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "validator_firehose_buffer" {
  description             = "Dedicated validator audit Firehose buffer encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.validator_firehose_buffer.json
  tags                    = local.common_tags
}

resource "aws_s3_bucket_notification" "validator_audit" {
  bucket      = aws_s3_bucket.validator_audit.id
  eventbridge = true
}
