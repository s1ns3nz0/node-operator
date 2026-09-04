#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

application="$root/docs/gitops/vault-application.example.yaml"
values="$root/docs/gitops/vault-values.example.yaml"
operations="$root/docs/gitops/vault-operations-contract.md"

for file in "$application" "$values" "$operations"; do
  test -f "$file" || fail "missing Vault GitOps contract file: $file"
done

grep -Fqx '    path: platform/vault' "$application" || fail "Vault Application must use the approved Vault path"
grep -Fqx '        - vault-values.yaml' "$application" || fail "Vault Application must consume reviewed values"

for required in \
  '  tlsDisable: false' \
  '    enabled: true' \
  '    replicas: 3' \
  '      enabled: true' \
  '      setNodeId: true' \
  '    type: ClusterIP' \
  '    enabled: false' \
  '        secretName: vault-tls' \
  '        seal "awskms" {' \
  '          kms_key_id = "REPLACE_WITH_VAULT_UNSEAL_KEY_ARN"'; do
  grep -Fqx "$required" "$values" || fail "Vault values missing required boundary: $required"
done

private_vault_repository='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-gitops-vault'
for image_tag in '268bb80aa9c6d13d65fcfa05c0c268caca068952240a8087291a6ce0b66e3a10' '8c18ccc87fd72930fd0c3f12ea444e9e57e83f119b93c546ed047aba29a05c5f'; do
  grep -Fqx "    repository: $private_vault_repository" "$values" || fail "Vault runtime image repository is not private ECR"
  grep -Fqx "    tag: $image_tag" "$values" || fail "Vault runtime image tag is not an approved immutable digest"
done

if grep -Eq '(type:[[:space:]]*(LoadBalancer|NodePort)|tls_disable[[:space:]]*=[[:space:]]*1|AWS_(ACCESS|SECRET)_ACCESS_KEY|aws_access_key|aws_secret_key)' "$values"; then
  fail "Vault values include a public, plaintext, or static-credential configuration"
fi

for required in \
  'hardened self-hosted runner' \
  'GitHub-hosted runners' \
  'audit device' \
  'snapshot restore test' \
  'fail-closed' \
  'static credential' \
  'public-endpoint fallback'; do
  grep -Fq "$required" "$operations" || fail "Vault operations contract omits: $required"
done

printf 'PASS Vault GitOps chart and private-runner contract is structurally constrained.\n'
