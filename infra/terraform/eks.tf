resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.audit.arn

  tags = local.common_tags
}

resource "aws_eks_cluster" "private" {
  name     = var.name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  upgrade_policy {
    # Avoid the higher EKS extended-support control-plane charge. A cluster
    # must be upgraded before its standard-support window ends.
    support_type = "STANDARD"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Preserve existing aws-auth compatibility while enabling Terraform-managed
  # access entries for the dedicated, VPC-internal GitOps bootstrap identity.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # EKS 1.28 and later automatically encrypts all Kubernetes API data with an
  # AWS-owned KMS key. Do not add a customer-managed key here: application
  # secrets belong to Vault, while AWS service encryption remains scoped to
  # the dedicated EBS and audit keys below.

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  depends_on = [
    aws_cloudwatch_log_group.eks_control_plane,
    aws_iam_role_policy_attachment.eks_cluster,
    aws_vpc_security_group_ingress_rule.cluster_api_from_nodes,
    aws_vpc_security_group_ingress_rule.nodes_self_all,
    aws_vpc_security_group_ingress_rule.nodes_kubelet_from_cluster,
    aws_vpc_security_group_ingress_rule.nodes_webhook_from_cluster,
  ]

  lifecycle {
    precondition {
      condition     = tonumber(split(".", var.kubernetes_version)[1]) >= 28
      error_message = "kubernetes_version must be 1.28 or later so EKS default envelope encryption protects all Kubernetes API data."
    }
  }

  tags = local.common_tags
}

resource "aws_launch_template" "nodes" {
  name_prefix            = "${local.name_prefix}-nodes-"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs.arn
      volume_size           = var.node_root_volume_size
      volume_type           = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.nodes.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = local.common_tags
}

resource "aws_eks_node_group" "private" {
  cluster_name    = aws_eks_cluster.private.name
  node_group_name = "${var.name}-managed"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr_read_only,
    aws_iam_role_policy_attachment.node_cni,
    aws_eks_addon.vpc_cni,
    aws_vpc_endpoint.required_interface,
    aws_vpc_endpoint.s3,
  ]

  tags = local.common_tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.private.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_cluster.private]

  tags = local.common_tags
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.private.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.private.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.private]

  tags = local.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.private.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Pod Identity is independent of the ServiceAccount's existence.  Creating
  # it first lets the EBS CSI controller receive AWS credentials on its first
  # start instead of leaving the managed add-on waiting for a later reconcile.
  depends_on = [
    aws_eks_node_group.private,
    aws_eks_addon.pod_identity_agent,
    aws_eks_pod_identity_association.ebs_csi,
  ]

  tags = local.common_tags
}

resource "aws_eks_pod_identity_association" "vault" {
  cluster_name    = aws_eks_cluster.private.name
  namespace       = "vault"
  service_account = "vault"
  role_arn        = aws_iam_role.vault.arn
}
