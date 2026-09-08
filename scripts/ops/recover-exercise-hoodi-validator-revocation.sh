#!/usr/bin/env bash
set -euo pipefail

# UC-5 runtime exercise. It uses a recovery-key ceremony to temporarily remove
# only this set's Vault Kubernetes role, proves the signer cannot start, then
# restores the reviewed role. It never reads or prints Vault values, recovery
# material, tokens, or keystores.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then
  exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" "$@"
fi

usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> --exercise-approval-id <id> --output-dir <absolute-dir>" >&2; exit 64; }
validator_set=''; approval_id=''; output_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --exercise-approval-id) approval_id="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$approval_id" in [a-zA-Z0-9][a-zA-Z0-9._:-]*) ;; *) usage ;; esac
case "$output_dir" in /*) ;; *) usage ;; esac
for command in vault jq kubectl mkdir chmod date sleep; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

namespace=validator-operations
role="hoodi-${validator_set}-runtime"
deployment="validator-${validator_set}-remote-signer"
client="validator-${validator_set}-client"
client_replicas="$(kubectl -n "$namespace" get deployment "$client" --ignore-not-found -o jsonpath='{.spec.replicas}')"
[ -z "$client_replicas" ] || [ "$client_replicas" = 0 ] || { printf '%s\n' 'validator client must be fenced at zero before UC-5' >&2; exit 65; }
[ "$(kubectl -n "$namespace" get deployment "$deployment" -o jsonpath='{.spec.replicas}')" = 1 ] || { printf '%s\n' 'signer must be running at one replica before UC-5' >&2; exit 65; }

started=false; complete=false; root_token=''
cleanup() {
  set +e
  [ -z "$root_token" ] || VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1 || true
  [ "$started" = true ] && [ "$complete" != true ] && vault operator generate-root -cancel >/dev/null 2>&1 || true
  unset VAULT_TOKEN root_token
}
trap cleanup EXIT INT TERM
status="$(vault operator generate-root -status -format=json)"
[ "$(jq -r '.started' <<<"$status")" = false ] || { printf '%s\n' 'root-token ceremony already in progress' >&2; exit 75; }
init="$(vault operator generate-root -init -format=json)"; started=true
nonce="$(jq -er .nonce <<<"$init")"; otp="$(jq -er .otp <<<"$init")"; required="$(jq -er .required <<<"$init")"
for share_number in $(seq 1 "$required"); do
  printf 'Recovery key share %s of %s: ' "$share_number" "$required" >&2
  IFS= read -r -s share; printf '\n' >&2
  submitted="$(printf %s "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share
  if [ "$(jq -r .complete <<<"$submitted")" = true ]; then complete=true; encoded="$(jq -er .encoded_token <<<"$submitted")"; break; fi
done
[ "$complete" = true ] || { printf '%s\n' 'recovery quorum was not reached' >&2; exit 77; }
root_token="$(vault operator generate-root -decode="$encoded" -otp="$otp")"; unset encoded otp nonce init submitted status

VAULT_TOKEN="$root_token" vault delete "auth/kubernetes/role/${role}" >/dev/null
kubectl -n "$namespace" rollout restart "deployment/${deployment}" >/dev/null
denied=false
for attempt in $(seq 1 60); do
  pod="$(kubectl -n "$namespace" get pods -l "app.kubernetes.io/component=validator-remote-signer,node-operator.io/validator-set=${validator_set}" -o json | jq -r '[.items[] | select(.metadata.creationTimestamp != null)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // empty')"
  if [ -n "$pod" ] && kubectl -n "$namespace" logs "$pod" -c vault-agent-init --tail=20 2>&1 | grep -Eq 'permission denied|invalid role|error authenticating'; then denied=true; break; fi
  sleep 5
done
[ "$denied" = true ] || { printf '%s\n' 'signer did not prove fail-closed; role remains revoked for investigation' >&2; exit 1; }

VAULT_TOKEN="$root_token" PRIVATE_VAULT_SESSION=1 "$dir/bootstrap-hoodi-validator-runtime-vault.sh" --validator-set "$validator_set" >/dev/null
kubectl -n "$namespace" rollout restart "deployment/${deployment}" >/dev/null
kubectl -n "$namespace" rollout status "deployment/${deployment}" --timeout=360s >/dev/null

mkdir -p "$output_dir"; chmod 700 "$output_dir"; output_dir="$(cd "$output_dir" && pwd -P)"
record="$output_dir/uc-5-role-revocation-$(date -u +%Y%m%dT%H%M%SZ).json"
jq -n --arg collected "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg approval "$approval_id" --arg set "$validator_set" --arg role "$role" \
  '{schema_version:1,event_type:"uc-5",collected_at_utc:$collected,network:"hoodi",validator_set:$set,source:"vault-audit",payload:{exercise_approval_id:$approval,revoked_kubernetes_auth_role:$role,signer_failed_closed:true,role_restored:true,signer_ready_after_restore:true,client_remained_fenced:true}}' > "$record"
chmod 600 "$record"
printf 'PASS UC-5: runtime role revocation failed closed and access was restored. Evidence: %s\n' "$record"
