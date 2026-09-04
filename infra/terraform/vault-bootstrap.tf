variable "enable_vault_bootstrap_runner" {
  description = "Create the dedicated VPC-internal CodeBuild executor for the approved sealed Vault Helm release."
  type        = bool
  default     = false
}

variable "enable_vault_bootstrap_cluster_admin" {
  description = "Temporarily grant cluster-admin only to the dedicated Vault bootstrap role for the initial reviewed Helm installation. Set false and apply immediately after the sealed-state evidence is accepted."
  type        = bool
  default     = false
}

variable "vault_bootstrap_subnet_ids" {
  description = "Explicit private subnet IDs for the Vault bootstrap executor."
  type        = list(string)
  default     = []
}

variable "vault_bootstrap_image" {
  description = "Digest-pinned private ECR image containing Helm, kubectl, AWS CLI, and the reviewed Vault values template."
  type        = string
  default     = ""

  validation {
    condition     = var.vault_bootstrap_image == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$", var.vault_bootstrap_image))
    error_message = "vault_bootstrap_image must be empty while disabled or a digest-pinned ap-northeast-2 private ECR image."
  }
}

variable "vault_chart_version" {
  description = "Approved Vault Helm chart version stored in private ECR."
  type        = string
  default     = ""

  validation {
    condition     = var.vault_chart_version == "" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.vault_chart_version))
    error_message = "vault_chart_version must be empty while disabled or a pinned semver version."
  }
}

variable "vault_chart_manifest_digest" {
  description = "Approved private ECR OCI manifest digest resolved by the pinned Vault chart version."
  type        = string
  default     = ""

  validation {
    condition     = var.vault_chart_manifest_digest == "" || can(regex("^sha256:[a-f0-9]{64}$", var.vault_chart_manifest_digest))
    error_message = "vault_chart_manifest_digest must be empty while disabled or an approved OCI sha256 manifest digest."
  }
}

resource "aws_security_group" "vault_bootstrap" {
  count       = var.enable_vault_bootstrap_runner ? 1 : 0
  name_prefix = "${local.name_prefix}-vault-bootstrap-"
  description = "Private Vault bootstrap executor egress only to the EKS API and approved VPC endpoints."
  vpc_id      = aws_vpc.private.id

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id, aws_security_group.endpoints.id]
    description     = "HTTPS to the private EKS API and approved interface endpoints"
  }

  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [var.offline_validation ? "pl-78a54011" : data.aws_prefix_list.s3[0].id]
    description     = "HTTPS to ECR-managed S3 layers through the gateway endpoint"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vault-bootstrap", Purpose = "private-vault-bootstrap" })
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_vault_bootstrap" {
  count                        = var.enable_vault_bootstrap_runner ? 1 : 0
  description                  = "Kubernetes API from private Vault bootstrap executor"
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.vault_bootstrap[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_iam_role" "vault_bootstrap" {
  count              = var.enable_vault_bootstrap_runner ? 1 : 0
  name               = "${local.name_prefix}-vault-bootstrap"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = local.common_tags
}

data "aws_iam_policy_document" "vault_bootstrap" {
  count = var.enable_vault_bootstrap_runner ? 1 : 0
  statement {
    sid       = "WriteOnlyBootstrapLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.vault_bootstrap[0].arn}:*"]
  }
  statement {
    sid       = "DescribeOnlyTargetCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.private.arn]
  }
  statement {
    sid = "ManageOnlyCodeBuildVpcNetworkInterface"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface",
      "ec2:DescribeDhcpOptions", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets", "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid       = "PullOnlyPrivateVaultArtifacts"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]
    resources = [aws_ecr_repository.private_gitops["vault"].arn, aws_ecr_repository.private_gitops["vault_chart"].arn]
  }
}

resource "aws_iam_role_policy" "vault_bootstrap" {
  count  = var.enable_vault_bootstrap_runner ? 1 : 0
  name   = "${local.name_prefix}-vault-bootstrap"
  role   = aws_iam_role.vault_bootstrap[0].id
  policy = data.aws_iam_policy_document.vault_bootstrap[0].json
}

resource "aws_cloudwatch_log_group" "vault_bootstrap" {
  count             = var.enable_vault_bootstrap_runner ? 1 : 0
  name              = "/aws/codebuild/${local.name_prefix}-vault-bootstrap"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_eks_access_entry" "vault_bootstrap" {
  count         = var.enable_vault_bootstrap_runner ? 1 : 0
  cluster_name  = aws_eks_cluster.private.name
  principal_arn = aws_iam_role.vault_bootstrap[0].arn
  type          = "STANDARD"
}

# The official Vault chart with injector enabled creates cluster-scoped RBAC
# and a MutatingWebhookConfiguration. This policy is deliberately opt-in and
# must be removed by a follow-up apply after the sealed installation check.
resource "aws_eks_access_policy_association" "vault_bootstrap_cluster_admin" {
  count         = var.enable_vault_bootstrap_runner && var.enable_vault_bootstrap_cluster_admin ? 1 : 0
  cluster_name  = aws_eks_cluster.private.name
  principal_arn = aws_iam_role.vault_bootstrap[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.vault_bootstrap]
}

resource "aws_codebuild_project" "vault_bootstrap" {
  count         = var.enable_vault_bootstrap_runner ? 1 : 0
  name          = "${local.name_prefix}-vault-bootstrap"
  description   = "One-purpose private Vault sealed-release executor; temporary EKS access is revoked after use."
  service_role  = aws_iam_role.vault_bootstrap[0].arn
  build_timeout = 30
  artifacts {
    type = "NO_ARTIFACTS"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = var.vault_bootstrap_image
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "SERVICE_ROLE"

    environment_variable {
      name  = "VAULT_UNSEAL_KEY_ARN"
      value = aws_kms_key.vault.arn
    }
    environment_variable {
      name  = "VAULT_CHART_MANIFEST_DIGEST"
      value = var.vault_chart_manifest_digest
    }
  }
  vpc_config {
    vpc_id             = aws_vpc.private.id
    subnets            = var.vault_bootstrap_subnet_ids
    security_group_ids = [aws_security_group.vault_bootstrap[0].id]
  }
  source {
    type      = "NO_SOURCE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        build:
          commands:
            - set -eu
            - aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.private.name}
            - kubectl get secret vault-tls --namespace vault --ignore-not-found -o name | grep -Fx 'secret/vault-tls'
            - aws ecr get-login-password --region ${var.aws_region} | helm registry login --username AWS --password-stdin ${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
            - test -n "$VAULT_UNSEAL_KEY_ARN"
            - test -n "$VAULT_CHART_MANIFEST_DIGEST"
            - test "$(aws ecr describe-images --region ${var.aws_region} --repository-name ${local.private_gitops_repositories.vault_chart} --image-ids imageTag=${var.vault_chart_version} --query 'imageDetails[0].imageDigest' --output text)" = "$VAULT_CHART_MANIFEST_DIGEST"
            - sed "s|REPLACE_WITH_VAULT_UNSEAL_KEY_ARN|$VAULT_UNSEAL_KEY_ARN|g" /opt/node-operator/vault-values.template.yaml > /tmp/vault-values.yaml
            - grep -Fq 'REPLACE_WITH_VAULT_UNSEAL_KEY_ARN' /tmp/vault-values.yaml && exit 1 || true
            - helm upgrade --install vault oci://${aws_ecr_repository.private_gitops["vault_chart"].repository_url}@${var.vault_chart_manifest_digest} --namespace vault --values /tmp/vault-values.yaml --atomic --timeout 15m
            - kubectl wait --namespace vault --for=condition=Ready pod --selector=app.kubernetes.io/name=vault --timeout=15m
    YAML
  }
  lifecycle {
    precondition {
      condition     = var.enable_private_gitops_foundation && var.vault_chart_version != "" && can(regex("^sha256:[a-f0-9]{64}$", var.vault_chart_manifest_digest)) && can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/${local.private_gitops_repositories.vault}@sha256:[a-f0-9]{64}$", var.vault_bootstrap_image)) && length(var.vault_bootstrap_subnet_ids) > 0 && alltrue([for subnet_id in var.vault_bootstrap_subnet_ids : can(regex("^subnet-[a-z0-9]+$", subnet_id))])
      error_message = "Enabled Vault bootstrap requires the private GitOps Vault ECR repository, pinned toolchain and chart manifest digests, a pinned chart version, and explicit private subnets. EKS cluster-admin is a separately gated deploy-stage association."
    }
  }
  tags       = local.common_tags
  depends_on = [aws_eks_access_policy_association.vault_bootstrap_cluster_admin]
}

output "vault_bootstrap_project_name" {
  value       = try(aws_codebuild_project.vault_bootstrap[0].name, null)
  description = "Private CodeBuild project for the Vault sealed-release bootstrap, or null while disabled."
}

output "vault_bootstrap_role_arn" {
  value       = try(aws_iam_role.vault_bootstrap[0].arn, null)
  description = "Dedicated Vault bootstrap role whose temporary EKS admin policy must be revoked after sealed verification."
}
