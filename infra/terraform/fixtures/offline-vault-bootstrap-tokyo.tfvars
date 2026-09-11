aws_account_id                       = "123456789012"
aws_region                           = "ap-northeast-1"
audit_replica_region                 = "ap-northeast-2"
name                                 = "node-operator"
availability_zones                   = ["ap-northeast-1a", "ap-northeast-1c"]
private_subnet_cidrs                 = ["10.80.0.0/20", "10.80.16.0/20"]
offline_validation                   = true
enable_private_gitops_foundation     = true
enable_vault_bootstrap_runner        = true
enable_vault_bootstrap_cluster_admin = true
vault_bootstrap_subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
vault_bootstrap_image                = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-vault@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
vault_chart_version                  = "0.31.0"
vault_chart_manifest_digest          = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
vault_runtime_images = {
  server      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault-server@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  agent       = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault-agent@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  injector    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault-injector@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  audit_relay = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/vault-audit-relay@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
}
cert_manager_runtime_images = {
  controller      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-cert-manager@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  webhook         = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-cert-manager@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  cainjector      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-cert-manager@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  startupapicheck = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/node-operator-baseline-gitops-cert-manager@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
}
cert_manager_chart_version         = "1.21.1"
cert_manager_chart_manifest_digest = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
