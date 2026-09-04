# Synthetic, non-secret input that exercises the dedicated Vault bootstrap
# executor. Never use these values for a live apply.
aws_account_id                   = "123456789012"
name                             = "node-operator"
availability_zones               = ["ap-northeast-2a", "ap-northeast-2c"]
private_subnet_cidrs             = ["10.80.0.0/20", "10.80.16.0/20"]
offline_validation               = true
enable_private_gitops_foundation = true

enable_vault_bootstrap_runner        = true
enable_vault_bootstrap_cluster_admin = true
vault_bootstrap_subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
vault_bootstrap_image                = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-gitops-vault@sha256:3674b70a8c02a7fd0734e8e0d7c7f4f33fe7701f30b4c6f21569877721d55d07"
vault_chart_version                  = "0.31.0"
