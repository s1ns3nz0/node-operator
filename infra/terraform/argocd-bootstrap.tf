variable "enable_argocd_bootstrap_runner" {
  description = "Create the one-purpose, VPC-internal CodeBuild executor used to install the reviewed private Argo CD chart."
  type        = bool
  default     = false
}

variable "enable_argocd_bootstrap_cluster_admin" {
  description = "Grant the temporary cluster-admin policy needed only while Helm installs the Argo CD control plane. Disable immediately after successful bootstrap."
  type        = bool
  default     = false
}

variable "argocd_bootstrap_subnet_ids" {
  description = "Explicit private subnet IDs for the Argo CD bootstrap executor. Required only when it is enabled."
  type        = list(string)
  default     = []
}

variable "argocd_bootstrap_image" {
  description = "Digest-pinned private ECR image containing Helm, kubectl, AWS CLI, and the reviewed Argo CD values. Required only when the executor is enabled."
  type        = string
  default     = ""

  validation {
    condition     = var.argocd_bootstrap_image == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$", var.argocd_bootstrap_image))
    error_message = "argocd_bootstrap_image must be empty while disabled or an ap-northeast-2 private ECR image pinned by a sha256 digest."
  }
}

locals {
  argocd_chart_version = "10.4.0"
}

resource "aws_security_group" "argocd_bootstrap" {
  count       = var.enable_argocd_bootstrap_runner ? 1 : 0
  name_prefix = "${local.name_prefix}-argocd-bootstrap-"
  description = "Private Argo CD bootstrap executor egress to the EKS API and approved VPC endpoints only."
  vpc_id      = aws_vpc.private.id

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id, aws_security_group.endpoints.id]
    description     = "HTTPS to the private EKS API and approved interface endpoints"
  }

  # ECR returns presigned URLs for image/chart layers in AWS-managed S3. The
  # gateway endpoint keeps this private; its managed prefix list is narrower
  # than a CIDR-based internet egress rule.
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.offline_validation ? "pl-78a54011" : data.aws_prefix_list.s3[0].id]
    description     = "HTTPS to ECR-managed S3 layers through the gateway endpoint"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-argocd-bootstrap"
    Purpose = "private-argocd-bootstrap"
  })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_argocd_bootstrap" {
  count                        = var.enable_argocd_bootstrap_runner ? 1 : 0
  description                  = "Kubernetes API from private Argo CD bootstrap executor"
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.argocd_bootstrap[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_iam_role" "argocd_bootstrap" {
  count = var.enable_argocd_bootstrap_runner ? 1 : 0
  name  = "${local.name_prefix}-argocd-bootstrap"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

data "aws_iam_policy_document" "argocd_bootstrap" {
  count = var.enable_argocd_bootstrap_runner ? 1 : 0

  statement {
    sid       = "WriteOnlyBootstrapLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.argocd_bootstrap[0].arn}:*"]
  }

  statement {
    sid       = "DescribeOnlyTargetCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.private.arn]
  }

  # CodeBuild creates and tears down an ENI in the explicitly configured
  # private subnets. These EC2 control-plane calls do not grant instance or
  # security-group mutation authority.
  statement {
    sid = "ManageOnlyCodeBuildVpcNetworkInterface"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullOnlyPrivateBootstrapImageAndChart"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.private_gitops["argocd"].arn]
  }
}

resource "aws_iam_role_policy" "argocd_bootstrap" {
  count  = var.enable_argocd_bootstrap_runner ? 1 : 0
  name   = "${local.name_prefix}-argocd-bootstrap"
  role   = aws_iam_role.argocd_bootstrap[0].id
  policy = data.aws_iam_policy_document.argocd_bootstrap[0].json
}

resource "aws_cloudwatch_log_group" "argocd_bootstrap" {
  count             = var.enable_argocd_bootstrap_runner ? 1 : 0
  name              = "/aws/codebuild/${local.name_prefix}-argocd-bootstrap"
  retention_in_days = 30
  tags              = local.common_tags
}

# This is intentionally a dedicated, temporary cluster-admin access entry.
# Helm installs Argo CD CRDs and cluster-scoped RBAC. It must be removed by
# disabling this runner after the bootstrap evidence is accepted; it is never
# granted to a GitHub OIDC principal.
resource "aws_eks_access_entry" "argocd_bootstrap" {
  count         = var.enable_argocd_bootstrap_runner ? 1 : 0
  cluster_name  = aws_eks_cluster.private.name
  principal_arn = aws_iam_role.argocd_bootstrap[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "argocd_bootstrap" {
  count         = var.enable_argocd_bootstrap_runner && var.enable_argocd_bootstrap_cluster_admin ? 1 : 0
  cluster_name  = aws_eks_cluster.private.name
  principal_arn = aws_iam_role.argocd_bootstrap[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.argocd_bootstrap]
}

resource "aws_codebuild_project" "argocd_bootstrap" {
  count         = var.enable_argocd_bootstrap_runner ? 1 : 0
  name          = "${local.name_prefix}-argocd-bootstrap"
  description   = "One-purpose private Argo CD bootstrap executor"
  service_role  = aws_iam_role.argocd_bootstrap[0].arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.argocd_bootstrap_image
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "SERVICE_ROLE"
  }

  vpc_config {
    vpc_id             = aws_vpc.private.id
    subnets            = var.argocd_bootstrap_subnet_ids
    security_group_ids = [aws_security_group.argocd_bootstrap[0].id]
  }

  # NO_SOURCE and an inline, immutable Terraform buildspec remove a mutable
  # repository/S3 input. The only deployment payload is the pinned ECR image.
  source {
    type      = "NO_SOURCE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        build:
          commands:
            - set -eu
            - aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.private.name}
            - aws ecr get-login-password --region ${var.aws_region} | helm registry login --username AWS --password-stdin ${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
            - helm upgrade --install argocd oci://${aws_ecr_repository.private_gitops["argocd"].repository_url} --version ${local.argocd_chart_version} --namespace argocd --create-namespace --values /opt/node-operator/argocd-private-values.yaml --atomic --timeout 10m
            - kubectl wait --namespace argocd --for=condition=Available deployment/argocd-server --timeout=10m
    YAML
  }

  lifecycle {
    precondition {
      condition = (
        var.enable_private_gitops_foundation &&
        can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/${local.private_gitops_repositories.argocd}@sha256:[a-f0-9]{64}$", var.argocd_bootstrap_image)) &&
        length(var.argocd_bootstrap_subnet_ids) > 0 &&
        alltrue([for subnet_id in var.argocd_bootstrap_subnet_ids : can(regex("^subnet-[a-z0-9]+$", subnet_id))])
      )
      error_message = "Enabled Argo CD bootstrap requires the private GitOps ECR foundation, an argocd-repository digest, and one or more explicit private subnet IDs."
    }
  }

  tags = local.common_tags

  depends_on = [aws_eks_access_policy_association.argocd_bootstrap]
}

output "argocd_bootstrap_project_name" {
  description = "Private CodeBuild project for the reviewed Argo CD bootstrap, or null while disabled."
  value       = try(aws_codebuild_project.argocd_bootstrap[0].name, null)
}
