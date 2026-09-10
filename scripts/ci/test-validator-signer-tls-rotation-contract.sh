#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal source-contract fragments
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/rotate-hoodi-validator-signer-tls.sh"
fail() { printf 'FAIL transport TLS rotation contract: %s\n' "$*" >&2; exit 1; }
test -x "$script" || fail 'rotation helper missing or not executable'
bash -n "$script"
for required in \
  'validator client must be scaled to zero' \
  'validator client Pod remains; TLS rotation refused' \
  'vault kv put -cas="$signer_version" "$base/signer-tls"' \
  'vault kv put -cas="$client_version" "$base/client-tls"' \
  'create configmap "$known"' \
  'known-clients=$scratch/known-clients' \
  'basicConstraints=critical,CA:TRUE' \
  'extendedKeyUsage=serverAuth' \
  'extendedKeyUsage=clientAuth' \
  'passout "file:$scratch/password"' \
  'vault token revoke -self' \
  'tls-rotation.hcl'; do
  grep -Fq "$required" "$script" || fail "missing required boundary: $required"
done
if grep -Eq 'kv (get|put).*(keystore|slashing-db-password)' "$script"; then
  fail 'TLS rotation must not read or write custody/slashing material'
fi
if grep -Eq 'create secret generic|kubectl.*create secret' "$script"; then
  fail 'TLS rotation must not create Kubernetes Secrets'
fi
if grep -Eq 'generate-root -decode=.*(encoded|otp)' "$script"; then
  fail 'root decode material must not enter process arguments'
fi
printf '%s\n' 'PASS: complete signer/client TLS rotation is client-zero-gated, CAS-guarded, Vault-only, and updates public known clients.'
