#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal source-contract assertions
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail() { printf 'FAIL Vault v2 secret-boundary contract: %s\n' "$*" >&2; exit 1; }
inventory="$root/docs/security/vault-v2-secret-inventory.md"
bootstrap="$root/scripts/ops/bootstrap-node-operator-vault-v2.sh"
coordinator="$root/scripts/ops/recover-and-bootstrap-hoodi-vault-v2.sh"
onboard="$root/scripts/ops/recover-and-onboard-hoodi-validator-keystore.sh"

for file in "$inventory" "$bootstrap" "$coordinator" "$onboard"; do test -f "$file" || fail "missing $file"; done
for path in \
  'nodes/hoodi/engine-api-jwt' \
  'validators/hoodi/<set>/runtime/keystore' \
  'node-operator-pki/' \
  'Never store in Vault'; do
  grep -Fq "$path" "$inventory" || fail "inventory missing $path"
done
grep -Fq 'vault secrets enable -path="$mount" -version=2 kv' "$root/scripts/ops/ensure-node-operator-runtime-kv-v2.sh" || fail 'runtime engine does not create KV v2'
grep -Fq 'vault secrets enable -path=node-operator-pki pki' "$bootstrap" || fail 'PKI engine bootstrap missing'
grep -Fq 'node-operator-pki/issue/validator-mtls' "$onboard" || fail 'onboarding does not use Vault PKI issuance'
grep -Fq 'bootstrap-hoodi-engine-api-vault.sh' "$coordinator" || fail 'coordinator misses Engine JWT role bootstrap'
grep -Fq 'bootstrap-hoodi-validator-runtime-vault.sh' "$coordinator" || fail 'coordinator misses validator role bootstrap'
scan_rc=0
grep -REn 'kv/(data|metadata)' "$root/deploy/nethermind" "$root/deploy/prysm" "$root/deploy/validator" "$root/deploy/vault/policies" >/dev/null || scan_rc=$?
if [ "$scan_rc" -eq 0 ]; then
  fail 'new workload manifests or policies still reference legacy kv/'
fi
[ "$scan_rc" -eq 1 ] || fail 'legacy path scan could not complete'
scan_rc=0
grep -En 'openssl req -x509|ca\.key|CAkey' "$onboard" "$root/scripts/ops/rotate-hoodi-validator-signer-tls.sh" >/dev/null || scan_rc=$?
if [ "$scan_rc" -eq 0 ]; then
  fail 'runtime onboarding or rotation handles a CA private key outside Vault PKI'
fi
[ "$scan_rc" -eq 1 ] || fail 'CA private-key scan could not complete'
bash -n "$bootstrap" "$coordinator" "$onboard"
grep -Fq 'printf '\''%s %s\n'\'' "$client" "$fingerprint"' "$root/scripts/ops/prepare-hoodi-vault-v2-transport.sh" || fail 'preparation known-client name differs from issued CN'
grep -Fq 'printf '\''validator-%s-client.validator-operations.svc %s\n'\''' "$onboard" || fail 'onboarding known-client name differs from issued CN'
grep -Fq 'printf '\''validator-%s-client.%s.svc %s\n'\'' "$validator_set" "$namespace"' "$root/scripts/ops/rotate-hoodi-validator-signer-tls.sh" || fail 'rotation known-client name differs from issued CN'
printf '%s\n' 'PASS: Vault v2 inventory, isolated engines, workload paths, PKI issuance, and recovery coordinator are consistent.'
