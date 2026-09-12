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
    condition     = var.argocd_bootstrap_image == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z]{2}-[a-z0-9-]+-[0-9]+\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$", var.argocd_bootstrap_image))
    error_message = "argocd_bootstrap_image must be empty while disabled or a same-region private ECR image pinned by a sha256 digest."
  }
}

variable "gitops_client_chart_version" {
  description = "Exact immutable GitOps client chart version emitted by the protected publisher."
  type        = string
  default     = ""

  validation {
    condition     = var.gitops_client_chart_version == "" || can(regex("^0\\.1\\.[0-9]+$", var.gitops_client_chart_version))
    error_message = "gitops_client_chart_version must be empty while disabled or a publisher-issued 0.1.N version."
  }
}

variable "gitops_client_chart_oci_digest" {
  description = "OCI digest that the exact GitOps client chart version must resolve to."
  type        = string
  default     = ""

  validation {
    condition     = var.gitops_client_chart_oci_digest == "" || can(regex("^sha256:[a-f0-9]{64}$", var.gitops_client_chart_oci_digest))
    error_message = "gitops_client_chart_oci_digest must be empty while disabled or an immutable sha256 digest."
  }
}

variable "cert_manager_chart_manifest_digest" {
  description = "OCI manifest digest for the reviewed cert-manager chart mirrored into the private ECR repository."
  type        = string
  default     = "sha256:62c4745561eccfd723678c6547500750ebef5a880d81ff670d33124ab335f877"

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.cert_manager_chart_manifest_digest))
    error_message = "cert_manager_chart_manifest_digest must be an OCI sha256 manifest digest."
  }
}

locals {
  argocd_chart_version       = "10.4.0"
  cert_manager_chart_version = "v1.21.1"
}

resource "aws_security_group" "argocd_bootstrap" {
  count       = var.enable_argocd_bootstrap_runner ? 1 : 0
  name_prefix = "${local.name_prefix}-argocd-bootstrap-"
  description = "Private Argo CD bootstrap executor egress to the EKS API and approved VPC endpoints only."
  vpc_id      = local.network_vpc_id

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
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
    ]
    # Keep this existing pull scope independent from unrelated additions to the
    # private GitOps repository map. The repository name is deterministic and
    # already enforced by the private GitOps foundation.
    resources = [
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.private_gitops_repositories.argocd}",
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.private_gitops_repositories.argocd_chart}",
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.private_gitops_repositories.cert_manager}",
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${local.private_gitops_repositories.cert_manager_chart}",
      aws_ecr_repository.gitops_client_chart[0].arn,
      # The v0.1.x release contract points Argo at the immutable baseline
      # chart repository. Keep this read-only ARN alongside the per-environment
      # repository so a zero-resource bootstrap can consume an approved bundle.
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/node-operator-baseline-gitops-client/node-operator-client",
    ]
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
    vpc_id             = local.network_vpc_id
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
            # Older approved bootstrap images may contain only the Argo CD
            # values file.  Rehydrate the reviewed, non-secret inputs from the
            # Terraform release bundle so the immutable image remains usable
            # without depending on a mutable repository or public network.
            - test -f /opt/node-operator/argocd-private-values.yaml || (echo '${base64encode(try(file("${path.module}/argocd-private-values.example.yaml"), file("${path.module}/../../docs/gitops/argocd-private-values.example.yaml")))}' | base64 -d > /opt/node-operator/argocd-private-values.yaml)
            - test -f /opt/node-operator/cert-manager-values.yaml || (echo '${base64encode(try(file("${path.module}/cert-manager-values.example.yaml"), file("${path.module}/../../docs/gitops/cert-manager-values.example.yaml")))}' | base64 -d > /opt/node-operator/cert-manager-values.yaml)
            - test -f /opt/node-operator/vault-tls-internal-ca.yaml || (echo '${base64encode(try(file("${path.module}/vault-tls-internal-ca.example.yaml"), file("${path.module}/../../docs/gitops/vault-tls-internal-ca.example.yaml")))}' | base64 -d > /opt/node-operator/vault-tls-internal-ca.yaml)
            # The release image embeds reviewed values, while repository names
            # are deployment-scoped. Rewrite only the non-secret ECR prefix at
            # runtime so a zero-resource account never pulls another stack's
            # images.
            # The reviewed values files carry the Seoul source registry as
            # provenance metadata.  Rewrite both the deployment prefix and
            # registry region before the private-cluster install; otherwise
            # nodes in a new region try to pull over a non-existent cross-
            # region ECR endpoint and remain in ImagePullBackOff.
            - sed -i -e 's#node-operator-baseline#${local.name_prefix}#g' -e 's#ap-northeast-2#${var.aws_region}#g' /opt/node-operator/argocd-private-values.yaml /opt/node-operator/cert-manager-values.yaml
            - helm upgrade --install argocd oci://${aws_ecr_repository.private_gitops["argocd_chart"].repository_url} --version ${local.argocd_chart_version} --namespace argocd --create-namespace --values /opt/node-operator/argocd-private-values.yaml --atomic --timeout 10m
            - kubectl wait --namespace argocd --for=condition=Available deployment/argocd-server --timeout=10m
            - helm upgrade --install cert-manager oci://${aws_ecr_repository.private_gitops["cert_manager_chart"].repository_url}@${var.cert_manager_chart_manifest_digest} --version ${local.cert_manager_chart_version} --namespace cert-manager --create-namespace --values /opt/node-operator/cert-manager-values.yaml --atomic --timeout 10m
            - kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager --timeout=10m
            - kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager-webhook --timeout=10m
            - kubectl wait --namespace cert-manager --for=condition=Available deployment/cert-manager-cainjector --timeout=10m
            - kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
            - kubectl label namespace vault pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/audit-version=latest pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest --overwrite
            - kubectl apply -f /opt/node-operator/vault-tls-internal-ca.yaml
            - kubectl -n vault wait --for=condition=Ready certificate/vault-internal-ca --timeout=10m
            - kubectl -n vault wait --for=condition=Ready certificate/vault-server-tls --timeout=10m
            - kubectl -n vault get secret vault-tls -o name | grep -Fx 'secret/vault-tls'
            - test "$(aws ecr describe-images --region ${var.aws_region} --repository-name ${aws_ecr_repository.gitops_client_chart[0].name} --image-ids imageTag=${var.gitops_client_chart_version} --query 'imageDetails[0].imageDigest' --output text)" = "${var.gitops_client_chart_oci_digest}"
            - |
              cat <<'EOF' | kubectl apply -f -
              apiVersion: rbac.authorization.k8s.io/v1
              kind: Role
              metadata:
                name: node-operator-private-cd-application-reader
                namespace: argocd
              rules:
                - apiGroups: ["argoproj.io"]
                  resources: ["applications"]
                  resourceNames: ["node-operator-client"]
                  verbs: ["get"]
              ---
              apiVersion: rbac.authorization.k8s.io/v1
              kind: RoleBinding
              metadata:
                name: node-operator-private-cd-application-reader
                namespace: argocd
              roleRef:
                apiGroup: rbac.authorization.k8s.io
                kind: Role
                name: node-operator-private-cd-application-reader
              subjects:
                - kind: Group
                  name: node-operator:gitops-private-cd-readers
                  apiGroup: rbac.authorization.k8s.io
              EOF
            - |
              password="$(aws ecr get-login-password --region ${var.aws_region})"
              kubectl -n argocd create secret generic argocd-ecr-oci \
                --from-literal=type=helm \
                --from-literal=url=${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/node-operator-baseline-gitops-client \
                --from-literal=username=AWS \
                --from-literal=password="$password" \
                --from-literal=enableOCI=true \
                --dry-run=client -o yaml | kubectl -n argocd apply -f -
              kubectl -n argocd label secret argocd-ecr-oci argocd.argoproj.io/secret-type=repo-creds --overwrite
            - |
              cat <<'EOF' | kubectl apply -f -
              apiVersion: argoproj.io/v1alpha1
              kind: Application
              metadata:
                name: node-operator-client
                namespace: argocd
              spec:
                project: default
                source:
                  repoURL: ${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/node-operator-baseline-gitops-client
                  chart: node-operator-client
                  targetRevision: ${var.gitops_client_chart_version}
                destination:
                  server: https://kubernetes.default.svc
                  namespace: node-operator
                syncPolicy:
                  automated:
                    prune: false
                    selfHeal: true
                  syncOptions:
                    - CreateNamespace=false
              EOF
    YAML
  }

  lifecycle {
    precondition {
      condition = (
        var.enable_private_gitops_foundation &&
        can(regex("^${var.aws_account_id}\\.dkr\\.ecr\\.${var.aws_region}\\.amazonaws\\.com/${local.private_gitops_repositories.argocd}@sha256:[a-f0-9]{64}$", var.argocd_bootstrap_image)) &&
        can(regex("^0\\.1\\.[0-9]+$", var.gitops_client_chart_version)) &&
        can(regex("^sha256:[a-f0-9]{64}$", var.gitops_client_chart_oci_digest)) &&
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
