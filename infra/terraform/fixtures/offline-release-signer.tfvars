# Synthetic, non-secret input for validating the enabled release signer plan.
# The subnet IDs are deliberately fake and must never be used for an apply.
aws_account_id       = "123456789012"
name                 = "node-operator"
availability_zones   = ["ap-northeast-2a", "ap-northeast-2c"]
private_subnet_cidrs = ["10.80.0.0/20", "10.80.16.0/20"]
offline_validation   = true

enable_release_signer     = true
release_signer_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
release_signer_image      = "ghcr.io/s1ns3nz0/node-operator/vault-release-signer@sha256:3674b70a8c02a7fd0734e8e0d7c7f4f33fe7701f30b4c6f21569877721d55d07"
