#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL validator runtime contract: %s\n' "$*" >&2; exit 1; }

validator_dir="$root/deploy/validator"
operations="$root/docs/operations/validator-key-operations.md"
onboarding_policy="$validator_dir/vault/onboarding-write.hcl"
signer_policy="$validator_dir/vault/remote-signer.hcl"
auth_role="$validator_dir/vault/remote-signer-kubernetes-auth-role.json"
for file in \
  "$validator_dir/kustomization.yaml" \
  "$validator_dir/namespace.yaml" \
  "$validator_dir/service-accounts.yaml" \
  "$validator_dir/network-policies.yaml" \
  "$validator_dir/fencing.yaml" \
  "$validator_dir/remote-signer-service.yaml" \
  "$validator_dir/onboarding-contract.yaml" \
  "$validator_dir/evidence-contract.yaml" \
  "$operations" \
  "$onboarding_policy" \
  "$signer_policy" \
  "$auth_role"; do
  test -f "$file" || fail "missing required artifact: $file"
done

require_command kubectl
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kubectl kustomize "$validator_dir" > "$rendered"

for required in \
  'name: validator-onboarding' \
  'name: validator-remote-signer' \
  'name: validator-client' \
  'name: validator-fence-controller' \
  'automountServiceAccountToken: false' \
  'name: hoodi-validator-set-primary' \
  'leaseDurationSeconds: 60' \
  'name: allow-validator-client-to-remote-signer' \
  'port: 9000' \
  'name: allow-remote-signer-vault-and-dns' \
  'port: 8200' \
  'type: ClusterIP' \
  'name: validator-onboarding-contract' \
  'name: validator-operations-evidence-contract'; do
  grep -Fq "$required" "$rendered" || fail "rendered contract omits: $required"
done

if grep -Eqi 'kind:[[:space:]]*Secret|vault_token:[[:space:]]*[^[:space:]]|client_token:[[:space:]]*[^[:space:]]|private_key:[[:space:]]*[^[:space:]]|seed_phrase:[[:space:]]*[^[:space:]]|withdrawal_credential:[[:space:]]*[^[:space:]]' "$validator_dir"/*.yaml; then
  fail 'validator manifests contain a secret-bearing resource or literal credential'
fi

if grep -Eq 'verbs:.*(\*|delete|create)' "$validator_dir/fencing.yaml"; then
  fail 'fencing RBAC must not create, delete, or wildcard Lease permissions'
fi

for required in \
  'REPLACE_WITH_VALIDATOR_SET/onboarding/keystore' \
  'REPLACE_WITH_VALIDATOR_SET/onboarding/password' \
  'capabilities = ["create", "update"]' \
  'path "transit/*"' \
  'capabilities = ["deny"]'; do
  grep -Fq "$required" "$onboarding_policy" || fail "onboarding policy omits: $required"
done

for required in \
  'REPLACE_WITH_VALIDATOR_SET/runtime/keystore' \
  'REPLACE_WITH_VALIDATOR_SET/runtime/password' \
  'capabilities = ["read"]' \
  'path "kv/metadata/validators/*"' \
  'path "transit/*"' \
  'path "auth/*"' \
  'path "sys/*"'; do
  grep -Fq "$required" "$signer_policy" || fail "remote signer policy omits: $required"
done

jq -e '
  .bound_service_account_names == ["validator-remote-signer"] and
  .bound_service_account_namespaces == ["validator-operations"] and
  .audience == "vault" and
  .token_ttl == "5m" and
  .token_max_ttl == "10m" and
  .token_no_default_policy == true
' "$auth_role" >/dev/null || fail 'remote signer Kubernetes auth role is not minimally bound'

for required in \
  'UC-2: onboarding and deposit preparation' \
  'UC-3: remote signer activation' \
  'UC-4: slashing protection and failover' \
  'UC-5: compromise, rotation, and voluntary exit' \
  'fail-closed' \
  'release Transit key'; do
  grep -Fq "$required" "$operations" || fail "operations runbook omits: $required"
done

printf 'PASS validator UC-2 through UC-5 runtime contracts preserve key and signer isolation.\n'
