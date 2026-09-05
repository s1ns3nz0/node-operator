variable "enable_gitops_client_ecr_publisher" {
  description = "Create the dedicated private ECR destination and GitHub OIDC publisher identity for the GitOps client repository."
  type        = bool
  default     = false
}

variable "gitops_client_github_repository" {
  description = "Exact non-secret GitHub repository allowed to publish the reviewed GitOps client OCI image."
  type        = string
  default     = "s1ns3nz0/node-operator-gitops"

  validation {
    condition     = var.gitops_client_github_repository == "s1ns3nz0/node-operator-gitops"
    error_message = "gitops_client_github_repository must remain s1ns3nz0/node-operator-gitops for this dedicated publisher boundary."
  }
}

variable "gitops_client_ecr_publisher_environment" {
  description = "Exact protected GitHub Actions environment allowed to exchange an OIDC token for the GitOps client ECR publisher role."
  type        = string
  default     = "gitops-client-ecr-publish"

  validation {
    condition     = var.gitops_client_ecr_publisher_environment == "gitops-client-ecr-publish"
    error_message = "gitops_client_ecr_publisher_environment must remain gitops-client-ecr-publish."
  }
}

locals {
  gitops_client_ecr_repository_name   = "${local.name_prefix}-gitops-client"
  gitops_client_chart_repository_name = "${local.gitops_client_ecr_repository_name}/node-operator-client"
}

# This repository is intentionally separate from private_gitops["nodes"].
# The client-repository publisher has no authority over charts, Vault, Argo CD,
# or the shared GitOps OCI mirror destinations.
resource "aws_ecr_repository" "gitops_client" {
  count                = var.enable_gitops_client_ecr_publisher ? 1 : 0
  name                 = local.gitops_client_ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name    = local.gitops_client_ecr_repository_name
    Purpose = "private-gitops-client-image"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Helm OCI appends Chart.yaml's name to the registry path. Keep the original
# boundary repository for audit continuity and create the exact chart path
# before publication, so the GitHub publisher never needs CreateRepository.
resource "aws_ecr_repository" "gitops_client_chart" {
  count                = var.enable_gitops_client_ecr_publisher ? 1 : 0
  name                 = local.gitops_client_chart_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name    = local.gitops_client_chart_repository_name
    Purpose = "private-gitops-client-chart"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "gitops_client" {
  count      = var.enable_gitops_client_ecr_publisher ? 1 : 0
  repository = aws_ecr_repository.gitops_client[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain the latest 10 immutable GitOps client images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "gitops_client_chart" {
  count      = var.enable_gitops_client_ecr_publisher ? 1 : 0
  repository = aws_ecr_repository.gitops_client_chart[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain the latest 10 immutable GitOps client charts"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

data "aws_iam_policy_document" "github_gitops_client_ecr_publisher_assume_role" {
  count = var.enable_gitops_client_ecr_publisher ? 1 : 0

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

    # Keep the repository claim and subject both exact. The alternate subject
    # form supports this organization's ID-bearing GitHub OIDC template while
    # retaining the same owner, repository, and protected environment.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = [var.gitops_client_github_repository]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.gitops_client_github_repository}:environment:${var.gitops_client_ecr_publisher_environment}",
        "repo:${split("/", var.gitops_client_github_repository)[0]}@*/${split("/", var.gitops_client_github_repository)[1]}@*:environment:${var.gitops_client_ecr_publisher_environment}",
      ]
    }
  }
}

resource "aws_iam_role" "github_gitops_client_ecr_publisher" {
  count              = var.enable_gitops_client_ecr_publisher ? 1 : 0
  name               = "${local.name_prefix}-github-gitops-client-ecr-publisher"
  assume_role_policy = data.aws_iam_policy_document.github_gitops_client_ecr_publisher_assume_role[0].json
  tags               = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "github_gitops_client_ecr_publisher" {
  count = var.enable_gitops_client_ecr_publisher ? 1 : 0

  # ECR requires the authorization-token action to use Resource "*". All
  # remaining actions are scoped to this one immutable client-image repository.
  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushOnlyGitOpsClientImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.gitops_client_chart[0].arn]
  }
}

resource "aws_iam_role_policy" "github_gitops_client_ecr_publisher" {
  count  = var.enable_gitops_client_ecr_publisher ? 1 : 0
  name   = "${local.name_prefix}-github-gitops-client-ecr-publisher"
  role   = aws_iam_role.github_gitops_client_ecr_publisher[0].id
  policy = data.aws_iam_policy_document.github_gitops_client_ecr_publisher[0].json
}

output "gitops_client_ecr_repository_url" {
  description = "Private immutable ECR Helm chart URL for the GitOps client, or null while the dedicated publisher boundary is disabled."
  value       = try(aws_ecr_repository.gitops_client_chart[0].repository_url, null)
}

output "github_gitops_client_ecr_publisher_role_arn" {
  description = "GitHub OIDC role ARN restricted to s1ns3nz0/node-operator-gitops and the protected gitops-client-ecr-publish environment, or null while disabled."
  value       = try(aws_iam_role.github_gitops_client_ecr_publisher[0].arn, null)
}
