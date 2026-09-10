#!/usr/bin/env bash
set -euo pipefail
umask 077

# Creates one Hoodi Engine API JWT inside Vault and grants it only to the
# paired Nethermind and Prysm Beacon service accounts.  The secret is never
# printed, written to Kubernetes, or accepted from command-line arguments.
usage() { printf 'Usage: %s\n' "${0##*/}" >&2; exit 64; }
[ "$#" -eq 0 ] || usage
for command in vault openssl jq; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
: "${VAULT_ADDR:?VAULT_ADDR must name the private Vault endpoint}"
: "${VAULT_TOKEN:?Supply a short-lived Vault administrator token through the secure environment}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
policy="$root/deploy/vault/policies/hoodi-engine-api.hcl"
nethermind_role="$root/deploy/vault/auth/hoodi-engine-nethermind-kubernetes-role.json"
prysm_role="$root/deploy/vault/auth/hoodi-engine-prysm-kubernetes-role.json"

vault read -format=json auth/kubernetes/config >/dev/null
vault policy write hoodi-engine-api "$policy" >/dev/null
vault write auth/kubernetes/role/hoodi-engine-nethermind @"$nethermind_role" >/dev/null
vault write auth/kubernetes/role/hoodi-engine-prysm @"$prysm_role" >/dev/null

if vault kv get -format=json kv/nodes/hoodi/engine-api-jwt >/dev/null 2>&1; then
  jwt="$(vault kv get -format=json kv/nodes/hoodi/engine-api-jwt | jq -er '.data.data.jwt | select(test("^[0-9a-f]{64}$"))')"
else
  jwt="$(openssl rand -hex 32)"
  vault kv put -cas=0 kv/nodes/hoodi/engine-api-jwt jwt="$jwt" >/dev/null
fi
unset jwt VAULT_TOKEN
printf '%s\n' 'PASS: Vault Engine API JWT and the isolated Nethermind/Prysm Kubernetes roles are configured. The JWT was not emitted.'
