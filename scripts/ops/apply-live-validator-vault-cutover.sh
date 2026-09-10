#!/usr/bin/env bash
set -euo pipefail
umask 077

# Stages validator mTLS cutover fail-closed. The caller supplies rendered,
# non-secret manifests and an already-collected fence proof. This script leaves
# the validator client at zero; UC-3/UC-4 evidence remains the only scale-up
# authority.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { printf 'Usage: %s --validator-set <hoodi-id> --expected-public-key <0x-key> --runtime-manifest <absolute-yaml> --client-manifest <absolute-yaml> --migration-evidence <absolute-json> --fence-proof <absolute-json> --evidence-output <new-absolute-json> --execute\n' "${0##*/}" >&2; exit 64; }
validator_set=''; public_key=''; runtime=''; client=''; migration=''; fence=''; evidence=''; execute=false
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) validator_set="${2:-}"; shift 2;; --expected-public-key) public_key="${2:-}"; shift 2;; --runtime-manifest) runtime="${2:-}"; shift 2;; --client-manifest) client="${2:-}"; shift 2;; --migration-evidence) migration="${2:-}"; shift 2;; --fence-proof) fence="${2:-}"; shift 2;; --evidence-output) evidence="${2:-}"; shift 2;; --execute) execute=true; shift;; *) usage;; esac; done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage;; esac
case "$runtime:$client:$migration:$fence:$evidence" in /*:/*:/*:/*:/*) ;; *) usage;; esac
[ "$execute" = true ] || usage
for file in "$runtime" "$client" "$migration" "$fence"; do [ -f "$file" ] && [ ! -L "$file" ] || { printf 'invalid input: %s\n' "$file" >&2; exit 65; }; done
[ ! -e "$evidence" ] && [ ! -L "$evidence" ] || { printf '%s\n' 'evidence output must be new' >&2; exit 65; }
if [ "${PRIVATE_EKS_SESSION:-}" != 1 ]; then exec "$dir/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 "$0" --validator-set "$validator_set" --expected-public-key "$public_key" --runtime-manifest "$runtime" --client-manifest "$client" --migration-evidence "$migration" --fence-proof "$fence" --evidence-output "$evidence" --execute; fi
for command in kubectl jq grep mkdir date sleep seq tr; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
jq -e --arg set "$validator_set" '.operation == "live-runtime-secret-migration" and .validator_set == $set and .source_secrets_retained == true' "$migration" >/dev/null
jq -e --arg set "$validator_set" --arg key "$(printf '%s' "$public_key" | tr '[:upper:]' '[:lower:]')" '.event_type == "signing-proxy-fence" and .validator_set == $set and .validator_public_key == $key and .payload.client_and_fence_quiesced == true and .payload.direct_client_to_signer_denied == true' "$fence" >/dev/null
if grep -Eq 'secretName:[[:space:]]*(validator-.*-(signer|client)-tls)|name:[[:space:]]*(signer-tls|client-tls)' "$runtime" "$client"; then printf '%s\n' 'rendered validator manifest still mounts legacy TLS Secret material' >&2; exit 65; fi
grep -Fq "node-operator-runtime/data/validators/hoodi/${validator_set}/runtime/signer-tls" "$runtime" || { printf '%s\n' 'runtime manifest lacks isolated Vault signer TLS injection' >&2; exit 65; }
grep -Fq "node-operator-runtime/data/validators/hoodi/${validator_set}/runtime/client-tls" "$client" || { printf '%s\n' 'client manifest lacks isolated Vault client TLS injection' >&2; exit 65; }
"$dir/assert-hoodi-validator-quiesced.sh" --validator-set "$validator_set" >/dev/null
rendered="$(kubectl apply --server-side --field-manager=node-operator-vault-cutover --dry-run=server -f "$runtime" -f "$client" -o json)"
jq -ne --arg set "$validator_set" --slurpfile documents /dev/stdin \
  -f "$dir/lib/validator-cutover-manifests.jq" <<<"$rendered" >/dev/null || {
  printf '%s\n' 'cutover manifests must contain only expected resources with signer/client at zero' >&2; exit 65;
}
"$dir/assert-hoodi-validator-quiesced.sh" --validator-set "$validator_set" >/dev/null
kubectl apply --server-side --field-manager=node-operator-vault-cutover -f "$runtime" -f "$client" >/dev/null
"$dir/assert-hoodi-validator-quiesced.sh" --validator-set "$validator_set" >/dev/null

namespace='validator-operations'; signer="validator-${validator_set}-remote-signer"; fence_deployment="validator-${validator_set}-signing-fence"; client_stateful="validator-${validator_set}-client"
kubectl -n "$namespace" scale deployment "$signer" --replicas=1 >/dev/null
kubectl -n "$namespace" rollout status "deployment/${signer}" --timeout=15m >/dev/null
signer_pod="$(kubectl -n "$namespace" get pods -l "app.kubernetes.io/component=validator-remote-signer,node-operator.io/validator-set=${validator_set}" -o json | jq -er '.items | select(length == 1) | .[0]')"
jq -e '[.status.initContainerStatuses[]? | select(.name == "vault-agent-init" and .state.terminated.exitCode == 0)] | length == 1' <<<"$signer_pod" >/dev/null || { printf '%s\n' 'signer Vault Agent init did not succeed' >&2; exit 70; }
kubectl -n "$namespace" scale deployment "$fence_deployment" --replicas=1 >/dev/null
kubectl -n "$namespace" rollout status "deployment/${fence_deployment}" --timeout=10m >/dev/null
client_replicas="$(kubectl -n "$namespace" get statefulset "$client_stateful" -o jsonpath='{.spec.replicas}')"
[ "$client_replicas" = 0 ] || { printf '%s\n' 'validator client must remain at zero after staged mTLS cutover' >&2; exit 70; }

mkdir -p "$(dirname "$evidence")"
jq -n --arg set "$validator_set" --arg key "$(printf '%s' "$public_key" | tr '[:upper:]' '[:lower:]')" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema_version:1,operation:"live-validator-vault-cutover",completed_at_utc:$at,validator_set:$set,validator_public_key:$key,signer_vault_init_succeeded:true,fence_restored:true,validator_client_replicas:0,legacy_tls_secrets_retained:true,secret_values_emitted:false}' > "$evidence"
chmod 600 "$evidence"
printf 'PASS: validator signer is Vault-mTLS backed; fence is restored and validator client remains fail-closed at zero. Evidence: %s\n' "$evidence"
