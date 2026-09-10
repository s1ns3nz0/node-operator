#!/usr/bin/env bash
set -euo pipefail

# This is the only client scale-up path. It is intentionally interactive in
# the sense that the caller must repeat public key and withdrawal address; it
# neither reaches a wallet nor accepts any secret value.
usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> --deposit-attestation <absolute-json> --public-deposit-verification <absolute-json> --private-evidence <absolute-json> --signer-evidence <absolute-json> --confirm-public-key <0x-key> --confirm-withdrawal-address <0x-address> [--dry-run]" >&2; exit 64; }
validator_set=''; deposit_attestation=''; public_deposit_verification=''; private_evidence=''; signer_evidence=''; public_key=''; withdrawal_address=''; dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --deposit-attestation) deposit_attestation="${2:-}"; shift 2 ;;
    --public-deposit-verification) public_deposit_verification="${2:-}"; shift 2 ;;
    --private-evidence) private_evidence="${2:-}"; shift 2 ;;
    --signer-evidence) signer_evidence="${2:-}"; shift 2 ;;
    --confirm-public-key) public_key="${2:-}"; shift 2 ;;
    --confirm-withdrawal-address) withdrawal_address="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
case "$withdrawal_address" in 0x????????????????????????????????????????) ;; *) usage ;; esac
case "$deposit_attestation" in /*) ;; *) usage ;; esac
case "$public_deposit_verification" in /*) ;; *) usage ;; esac
case "$private_evidence" in /*) ;; *) usage ;; esac
case "$signer_evidence" in /*) ;; *) usage ;; esac
for command in jq kubectl date tr; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
[ -r "$deposit_attestation" ] && [ -r "$public_deposit_verification" ] && [ -r "$private_evidence" ] && [ -r "$signer_evidence" ] || { printf '%s\n' 'activation evidence is not readable' >&2; exit 66; }

public_key="$(printf '%s' "$public_key" | tr '[:upper:]' '[:lower:]')"
expected_key="$(jq -r '.validator_public_key // empty' "$deposit_attestation" | tr '[:upper:]' '[:lower:]')"
expected_withdrawal="$(jq -r '.withdrawal_address // empty' "$deposit_attestation" | tr '[:upper:]' '[:lower:]')"
[ "$expected_key" = "$public_key" ] || { printf '%s\n' 'public-key confirmation does not match the deposit attestation' >&2; exit 65; }
[ "$expected_withdrawal" = "$(printf '%s' "$withdrawal_address" | tr '[:upper:]' '[:lower:]')" ] || { printf '%s\n' 'withdrawal-address confirmation does not match the deposit attestation' >&2; exit 65; }
confirmed_withdrawal="$(printf '%s' "$withdrawal_address" | tr '[:upper:]' '[:lower:]')"
jq -e --arg key "$public_key" --arg set "$validator_set" --arg withdrawal "0x010000000000000000000000${confirmed_withdrawal#0x}" '
  .network == "hoodi" and .chain_id == 560048 and .validator_set == $set and .validator_public_key == $key and
  .withdrawal_credentials == $withdrawal and .deposit_amount_gwei == 32000000000 and
  .receipt_status == "0x1" and .ssz_roots_match == true and .bls_signature_valid == true and
  .event_matches_public_file == true and .secret_material_accessed == false
' "$public_deposit_verification" >/dev/null || { printf '%s\n' 'public deposit proof is incomplete or identifies another validator' >&2; exit 65; }
now_epoch="$(date -u +%s)"
jq -e --arg key "$public_key" --arg set "$validator_set" --argjson now "$now_epoch" '
  def rfc3339_epoch:
    if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
    then sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    else error("invalid UTC RFC3339 timestamp")
    end;
  (.collected_at_utc | rfc3339_epoch) as $observed |
  (.schema_version == 1 and .event_type == "uc-3" and .network == "hoodi" and
   .validator_set == $set and .source == "private-beacon" and .validator_public_key == $key and
   ($observed <= ($now + 30)) and (($now - $observed) <= 300) and
   (.payload.syncing.is_syncing == false) and
   (.payload.syncing.is_optimistic == false) and
   (.payload.syncing.el_offline == false) and
   (.payload.validator_http_status == "200") and
   (.payload.validator.status == "active_ongoing") and
   (.payload.validator.validator.pubkey == $key) and
   (.payload.validator.index | tostring | test("^[0-9]+$")))
' "$private_evidence" >/dev/null || { printf '%s\n' 'private Beacon evidence does not prove an active, synced validator' >&2; exit 65; }
jq -e --arg key "$public_key" --arg set "$validator_set" --argjson now "$now_epoch" '
  def rfc3339_epoch:
    if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
    then sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    else error("invalid UTC RFC3339 timestamp")
    end;
  (.collected_at_utc | rfc3339_epoch) as $observed |
  (.schema_version == 1 and .event_type == "signer-public-key" and .network == "hoodi" and
   .validator_set == $set and
   .validator_public_key == $key and
   (.source == "web3signer-tls" or
    (.source == "vault-injected-mtls-get-only-probe" and .vault_agent_init_succeeded == true)) and
   .tls_verified == true and .public_key_count == 1 and .public_key_match == true and
   ($observed <= ($now + 30)) and (($now - $observed) <= 300))
' "$signer_evidence" >/dev/null || { printf '%s\n' 'fresh TLS-verified signer identity evidence is missing or mismatched' >&2; exit 65; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
allowlist="$root/.ci/validator/approved-client-images.json"
client="validator-${validator_set}-client"
client_pod="${client}-0"
fence="validator-${validator_set}-signing-fence"
signer="validator-${validator_set}-remote-signer"
lease="validator-${validator_set}-primary"
client_selector='app.kubernetes.io/component=validator-client'
client_deployments="$(kubectl get deployments --all-namespaces -l "$client_selector" -o json)"
client_pods="$(kubectl get pods --all-namespaces -l "$client_selector" -o json)"
client_statefulsets="$(kubectl get statefulsets --all-namespaces -l "$client_selector" -o json)"
fences="$(kubectl get deployments --all-namespaces -l "app.kubernetes.io/component=validator-signing-fence" -o json)"
[ "$(jq -r '.items | length' <<<"$client_deployments")" -eq 0 ] || { printf '%s\n' 'validator client Deployments exist cluster-wide; stable StatefulSet identity is required' >&2; exit 65; }
jq -e --arg namespace validator-operations --arg client "$client" --arg set "$validator_set" '
  (.items | type == "array" and length == 1) and
  (.items[0].metadata.namespace == $namespace) and
  (.items[0].metadata.name == $client) and
  (.items[0].metadata.labels["node-operator.io/validator-set"] == $set) and
  (.items[0].spec.template.metadata.labels["node-operator.io/validator-set"] == $set) and
  (.items[0].spec.serviceName == ("validator-" + $set + "-client-headless")) and
  (.items[0].spec.replicas == 0) and
  (.items[0].spec.template.spec.containers | type == "array" and length == 1) and
  (.items[0].spec.template.spec.containers[0].name == "validator") and
  (.items[0].spec.template.spec.containers[0].image | type == "string")
' <<<"$client_statefulsets" >/dev/null || { printf '%s\n' 'expected exactly one exact, zero-replica staged validator client StatefulSet cluster-wide' >&2; exit 65; }
client_image="$(jq -er '.items[0].spec.template.spec.containers[0].image' <<<"$client_statefulsets")"
jq -e --arg image "$client_image" '.schema_version == 2 and any(.images[]; .private_image == $image and .activation_approved == true and (.release_channel == "upstream-mirror" or .release_channel == "manual-native-mtls"))' "$allowlist" >/dev/null || { printf '%s\n' 'staged validator client image is not an exact activation-approved reviewed artifact' >&2; exit 65; }
[ "$(jq -r '.items | if type == "array" then length else -1 end' <<<"$client_pods")" -eq 0 ] || { printf '%s\n' 'validator client Pods exist cluster-wide; refuse activation' >&2; exit 65; }
jq -e --arg namespace validator-operations --arg fence "$fence" --arg set "$validator_set" '
  (.items | type == "array" and length == 1) and .items[0].metadata.namespace == $namespace and
  .items[0].metadata.name == $fence and .items[0].metadata.labels["node-operator.io/validator-set"] == $set and
  .items[0].spec.template.metadata.labels["node-operator.io/validator-set"] == $set and .items[0].spec.replicas == 0 and
  (.items[0].spec.template.spec.containers[0].image | test("/node-operator-baseline-validator-fence@sha256:[a-f0-9]{64}$"))
' <<<"$fences" >/dev/null || { printf '%s\n' 'expected exactly one exact, zero-replica digest-pinned signing fence' >&2; exit 65; }
public_service="$(kubectl -n validator-operations get service "$signer" -o json)"
direct_service="$(kubectl -n validator-operations get service "${signer}-direct" -o json)"
jq -e --arg set "$validator_set" '.spec.selector["app.kubernetes.io/component"] == "validator-signing-fence" and .spec.selector["node-operator.io/validator-set"] == $set and any(.spec.ports[]; .port == 9000 and .targetPort == "fence-proxy")' <<<"$public_service" >/dev/null || { printf '%s\n' 'public signer Service does not enforce the signing fence' >&2; exit 65; }
jq -e --arg set "$validator_set" '.spec.selector["app.kubernetes.io/component"] == "validator-remote-signer" and .spec.selector["node-operator.io/validator-set"] == $set and any(.spec.ports[]; .port == 9000 and .targetPort == "signer-api")' <<<"$direct_service" >/dev/null || { printf '%s\n' 'direct signer Service is missing or mis-scoped' >&2; exit 65; }
signer_replicas="$(kubectl -n validator-operations get deployment "$signer" -o jsonpath='{.spec.replicas}')"
[ "$signer_replicas" = 1 ] || { printf '%s\n' 'signer is not fenced and running at exactly one replica' >&2; exit 65; }
if [ "$dry_run" = true ]; then printf '%s\n' 'PASS: activation preflight passed; client and signing fence remain at zero because --dry-run was set.'; exit 0; fi

activation_complete=false
rollback() {
  status=$?; trap - EXIT INT TERM HUP
  if [ "$activation_complete" != true ]; then
    cleanup_failed=false
    kubectl -n validator-operations scale deployment "$fence" --replicas=0 >/dev/null 2>&1 || cleanup_failed=true
    kubectl -n validator-operations scale statefulset "$client" --replicas=0 >/dev/null 2>&1 || cleanup_failed=true
    fence_after="$(kubectl -n validator-operations get deployment "$fence" -o jsonpath='{.spec.replicas}' 2>/dev/null)" || cleanup_failed=true
    client_after="$(kubectl -n validator-operations get statefulset "$client" -o jsonpath='{.spec.replicas}' 2>/dev/null)" || cleanup_failed=true
    [ "${fence_after:-}" = 0 ] && [ "${client_after:-}" = 0 ] || cleanup_failed=true
    if [ "$cleanup_failed" = true ]; then
      printf '%s\n' 'CRITICAL: activation failed and zero-replica rollback could not be verified' >&2
      exit 70
    fi
  fi
  exit "$status"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
# The public signer Service has no endpoints while the fence is zero, and
# direct signer ingress accepts only the fence. Starting the fixed-name client
# first therefore cannot sign; it only establishes the Pod UID/IP to bind.
kubectl -n validator-operations scale statefulset "$client" --replicas=1
kubectl -n validator-operations rollout status statefulset "$client" --timeout=120s
client_json="$(kubectl -n validator-operations get pod "$client_pod" -o json)"
jq -e --arg set "$validator_set" --arg name "$client_pod" '
  .metadata.name == $name and .metadata.labels["node-operator.io/validator-set"] == $set and
  .metadata.labels["app.kubernetes.io/component"] == "validator-client" and
  (.metadata.uid | type == "string" and length > 0) and (.status.podIP | type == "string" and length > 0) and
  .status.phase == "Running" and any(.status.conditions[]; .type == "Ready" and .status == "True")
' <<<"$client_json" >/dev/null || { printf '%s\n' 'fixed client Pod identity is not Ready for fence binding' >&2; exit 65; }
kubectl -n validator-operations scale deployment "$fence" --replicas=1
kubectl -n validator-operations rollout status deployment "$fence" --timeout=120s
fence_pod="$(kubectl -n validator-operations get pods -l "app.kubernetes.io/component=validator-signing-fence,node-operator.io/validator-set=${validator_set}" -o json)"
fence_uid="$(jq -er 'select(.items | length == 1) | .items[0].metadata.uid' <<<"$fence_pod")"
lease_json="$(kubectl -n validator-operations get lease "$lease" -o json)"
jq -e --arg holder "$fence_uid" --argjson now "$(date -u +%s)" '
  def rfc3339_epoch:
    if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")
    then sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
    else error("invalid UTC RFC3339 timestamp")
    end;
  (.spec.renewTime | rfc3339_epoch) as $renewed |
  ((.spec.holderIdentity == $holder) and
   (.spec.leaseDurationSeconds | type == "number" and . > 0) and
   ($renewed <= ($now + 30)) and (($now - $renewed) <= .spec.leaseDurationSeconds))
' <<<"$lease_json" >/dev/null || { printf '%s\n' 'signer fence lease is absent, malformed, or expired' >&2; exit 65; }
activation_complete=true
trap - EXIT INT TERM HUP
printf '%s\n' 'PASS: one fixed-identity client and its signing fence are Ready. Immediately collect private duty, signer audit, and Kubernetes evidence; never start a second client.'
