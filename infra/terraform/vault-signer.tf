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

variable "github_repository" {
  description = "GitHub repository allowed to start the release signer, owner/name."
  type        = string
  default     = "s1ns3nz0/node-operator"
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
  name               = "${local.name_prefix}-release-signer"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = local.common_tags
}

data "aws_iam_policy_document" "release_codebuild_signer" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "release_codebuild_signer" {
  role   = aws_iam_role.release_codebuild_signer.id
  policy = data.aws_iam_policy_document.release_codebuild_signer.json
}

resource "aws_codebuild_project" "release_signer" {
  count         = var.enable_release_signer ? 1 : 0
  name          = "${local.name_prefix}-release-signer"
  service_role  = aws_iam_role.release_codebuild_signer.arn
  build_timeout = 30
  artifacts { type = "NO_ARTIFACTS" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }
  vpc_config {
    vpc_id             = aws_vpc.node_operator.id
    subnet_ids         = var.release_signer_subnet_ids
    security_group_ids = [aws_security_group.cluster.id]
  }
  source { type = "NO_SOURCE" }
  tags = local.common_tags
}
