variable "vault_signer_endpoint" {
  description = "Private Vault Transit signer endpoint; never a public URL."
  type        = string
  default     = ""
  validation {
    condition     = var.vault_signer_endpoint == "" || can(regex("^https://", var.vault_signer_endpoint))
    error_message = "vault_signer_endpoint must be HTTPS when configured."
  }
}

resource "aws_iam_role" "release_codebuild_signer" {
  name = "${local.name_prefix}-release-signer"
  assume_role_policy = jsonencode({Version="2012-10-17",Statement=[{Effect="Allow",Principal={Service="codebuild.amazonaws.com"},Action="sts:AssumeRole"}]})
  tags = local.common_tags
}

data "aws_iam_policy_document" "release_codebuild_signer" {
  statement {
    sid = "Logs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "release_codebuild_signer" {
  role   = aws_iam_role.release_codebuild_signer.id
  policy = data.aws_iam_policy_document.release_codebuild_signer.json
}
