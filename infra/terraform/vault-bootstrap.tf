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
    condition     = var.vault_bootstrap_image == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-(1|2)\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$", var.vault_bootstrap_image))
    error_message = "vault_bootstrap_image must be empty while disabled or a digest-pinned private ECR image in a supported Region."
  }
}

variable "vault_runtime_images" {
  description = "Digest-pinned private ECR runtime images for the sealed Vault release."
  type        = map(string)
  default     = {}
}

variable "cert_manager_runtime_images" {
  description = "Four digest-pinned private cert-manager images required before Vault TLS."
  type        = map(string)
  default     = {}
}

variable "cert_manager_chart_version" {
  type    = string
  default = ""
}
variable "cert_manager_chart_manifest_digest" {
  type    = string
  default = ""
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
  vpc_id      = local.network_vpc_id

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
    sid     = "PullOnlyPrivateVaultArtifacts"
    actions = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]
    # Keep the existing Vault pull scope stable when other private GitOps
    # repositories are added. These deterministic names remain the only two
    # repositories the runner can read.
    resources = [
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.private_gitops_repositories.vault}",
      aws_ecr_repository.private_gitops["vault_chart"].arn,
      aws_ecr_repository.private_gitops["cert_manager_chart"].arn,
    ]
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
      name  = "VAULT_SERVER_IMAGE"
      value = var.vault_runtime_images["server"]
    }
    environment_variable {
      name  = "VAULT_AGENT_IMAGE"
      value = var.vault_runtime_images["agent"]
    }
    environment_variable {
      name  = "VAULT_INJECTOR_IMAGE"
      value = var.vault_runtime_images["injector"]
    }
    environment_variable {
      name  = "VAULT_AUDIT_RELAY_IMAGE"
      value = var.vault_runtime_images["audit_relay"]
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.aws_account_id
    }
    environment_variable {
      name  = "VAULT_CHART_MANIFEST_DIGEST"
      value = var.vault_chart_manifest_digest
    }
    environment_variable {
      name  = "CERT_MANAGER_CONTROLLER_IMAGE"
      value = var.cert_manager_runtime_images["controller"]
    }
    environment_variable {
      name  = "CERT_MANAGER_WEBHOOK_IMAGE"
      value = var.cert_manager_runtime_images["webhook"]
    }
    environment_variable {
      name  = "CERT_MANAGER_CAINJECTOR_IMAGE"
      value = var.cert_manager_runtime_images["cainjector"]
    }
    environment_variable {
      name  = "CERT_MANAGER_STARTUPAPICHECK_IMAGE"
      value = var.cert_manager_runtime_images["startupapicheck"]
    }
    environment_variable {
      name  = "CERT_MANAGER_CHART_MANIFEST_DIGEST"
      value = var.cert_manager_chart_manifest_digest
    }
  }
  vpc_config {
    vpc_id             = local.network_vpc_id
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
            - aws ecr get-login-password --region ${var.aws_region} | helm registry login --username AWS --password-stdin ${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
            - test "$(aws ecr describe-images --region ${var.aws_region} --repository-name ${local.private_gitops_repositories.cert_manager_chart} --image-ids imageTag=${var.cert_manager_chart_version} --query 'imageDetails[0].imageDigest' --output text)" = "$CERT_MANAGER_CHART_MANIFEST_DIGEST"
            - cert_values_dir=$(mktemp -d /tmp/node-operator-cert-manager-values.XXXXXX)
            - python3 /opt/node-operator/render-private-cert-manager-values.py --template /opt/node-operator/cert-manager-values.template.yaml --output "$cert_values_dir/values.yaml" --aws-account-id "$AWS_ACCOUNT_ID" --aws-region ${var.aws_region} --controller-image "$CERT_MANAGER_CONTROLLER_IMAGE" --webhook-image "$CERT_MANAGER_WEBHOOK_IMAGE" --cainjector-image "$CERT_MANAGER_CAINJECTOR_IMAGE" --startupapicheck-image "$CERT_MANAGER_STARTUPAPICHECK_IMAGE"
            - /opt/node-operator/deploy-private-cert-manager.sh --chart "oci://${aws_ecr_repository.private_gitops["cert_manager_chart"].repository_url}@${var.cert_manager_chart_manifest_digest}" --values "$cert_values_dir/values.yaml"
            - /opt/node-operator/prepare-vault-bootstrap-tls.sh --manifest /opt/node-operator/vault-tls.yaml
            - test -n "$VAULT_UNSEAL_KEY_ARN"
            - test -n "$VAULT_CHART_MANIFEST_DIGEST"
            - test "$(aws ecr describe-images --region ${var.aws_region} --repository-name ${local.private_gitops_repositories.vault_chart} --image-ids imageTag=${var.vault_chart_version} --query 'imageDetails[0].imageDigest' --output text)" = "$VAULT_CHART_MANIFEST_DIGEST"
            - vault_values_dir=$(mktemp -d /tmp/node-operator-vault-values.XXXXXX)
            - /opt/node-operator/render-private-vault-values.sh --template /opt/node-operator/vault-values.template.yaml --output "$vault_values_dir/values.yaml" --aws-account-id "$AWS_ACCOUNT_ID" --aws-region ${var.aws_region} --unseal-key-arn "$VAULT_UNSEAL_KEY_ARN" --server-image "$VAULT_SERVER_IMAGE" --agent-image "$VAULT_AGENT_IMAGE" --injector-image "$VAULT_INJECTOR_IMAGE" --audit-relay-image "$VAULT_AUDIT_RELAY_IMAGE"
            - /opt/node-operator/deploy-sealed-vault.sh --chart "oci://${aws_ecr_repository.private_gitops["vault_chart"].repository_url}@${var.vault_chart_manifest_digest}" --values "$vault_values_dir/values.yaml"
    YAML
  }
  lifecycle {
    precondition {
      condition     = var.enable_private_gitops_foundation && var.vault_chart_version != "" && can(regex("^sha256:[a-f0-9]{64}$", var.vault_chart_manifest_digest)) && can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/${local.private_gitops_repositories.vault}@sha256:[a-f0-9]{64}$", var.vault_bootstrap_image)) && length(var.vault_runtime_images) == 4 && alltrue([for key in ["server", "agent", "injector", "audit_relay"] : can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$", try(var.vault_runtime_images[key], "")))]) && length(var.cert_manager_runtime_images) == 4 && can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cert_manager_chart_version)) && can(regex("^sha256:[a-f0-9]{64}$", var.cert_manager_chart_manifest_digest)) && alltrue([for key in ["controller", "webhook", "cainjector", "startupapicheck"] : can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/${local.private_gitops_repositories.cert_manager}@sha256:[a-f0-9]{64}$", try(var.cert_manager_runtime_images[key], "")))]) && length(var.vault_bootstrap_subnet_ids) > 0 && alltrue([for subnet_id in var.vault_bootstrap_subnet_ids : can(regex("^subnet-[a-z0-9]+$", subnet_id))])
      error_message = "Enabled Vault bootstrap requires pinned private Vault and cert-manager artifacts, pinned toolchain and chart manifest digests, their chart versions, and explicit private subnets. EKS cluster-admin is a separately gated deploy-stage association."
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

output "vault_bootstrap_project_contract" {
  description = "Non-secret immutable identity and buildspec binding for the guarded Vault platform executor."
  sensitive   = false
  value = try({
    name             = aws_codebuild_project.vault_bootstrap[0].name
    arn              = aws_codebuild_project.vault_bootstrap[0].arn
    service_role_arn = aws_iam_role.vault_bootstrap[0].arn
    image            = var.vault_bootstrap_image
    source_type      = aws_codebuild_project.vault_bootstrap[0].source[0].type
    buildspec_sha256 = sha256(aws_codebuild_project.vault_bootstrap[0].source[0].buildspec)
    aws_account_id   = var.aws_account_id
    aws_region       = var.aws_region
  }, null)
}
