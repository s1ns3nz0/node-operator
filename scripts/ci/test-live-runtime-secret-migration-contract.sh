#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal source-contract fragments
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/recover-and-migrate-hoodi-runtime-secrets-to-vault.sh"
fail() { printf 'FAIL live runtime secret migration contract: %s\n' "$*" >&2; exit 1; }
test -x "$script" || fail 'migration helper missing or not executable'
bash -n "$script"
for required in \
  'get secret engine-api-jwt -o json' \
  'get secret "validator-${validator_set}-signer-tls" -o json' \
  'get secret "validator-${validator_set}-client-tls" -o json' \
  'put_or_match "$engine_path"' \
  'put_or_match "$base/signer-tls"' \
  'put_or_match "$base/client-tls"' \
  'vault kv put -cas=0 "$path"' \
  'bootstrap-hoodi-engine-api-vault.sh' \
  'bootstrap-hoodi-validator-runtime-vault.sh' \
  'source_secrets_retained:true' \
  'vault_recovery_decode_generated_root' \
  'vault token revoke -self'; do
  grep -Fq "$required" "$script" || fail "missing required migration boundary: $required"
done
if grep -Eq 'openssl rand|kubectl.*delete secret|create secret generic|generate-root -decode' "$script"; then
  fail 'migration must neither generate nor delete/reprint source secret material'
fi
printf '%s\n' 'PASS: live runtime migration preserves existing JWT/TLS material, writes Vault records with CAS, and retains source Secrets for staged cutover.'
