#!/usr/bin/env bash
set -euo pipefail

# This is the only client scale-up path. It is intentionally interactive in
# the sense that the caller must repeat public key and withdrawal address; it
# neither reaches a wallet nor accepts any secret value.
usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> --deposit-attestation <absolute-json> --private-evidence <absolute-json> --confirm-public-key <0x-key> --confirm-withdrawal-address <0x-address> [--dry-run]" >&2; exit 64; }
validator_set=''; deposit_attestation=''; private_evidence=''; public_key=''; withdrawal_address=''; dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --deposit-attestation) deposit_attestation="${2:-}"; shift 2 ;;
    --private-evidence) private_evidence="${2:-}"; shift 2 ;;
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
case "$private_evidence" in /*) ;; *) usage ;; esac
for command in jq kubectl; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
[ -r "$deposit_attestation" ] && [ -r "$private_evidence" ] || { printf '%s\n' 'attestation or private evidence is not readable' >&2; exit 66; }

public_key="$(printf '%s' "$public_key" | tr '[:upper:]' '[:lower:]')"
expected_key="$(jq -r '.validator_public_key // empty' "$deposit_attestation" | tr '[:upper:]' '[:lower:]')"
expected_withdrawal="$(jq -r '.withdrawal_address // empty' "$deposit_attestation" | tr '[:upper:]' '[:lower:]')"
[ "$expected_key" = "$public_key" ] || { printf '%s\n' 'public-key confirmation does not match the deposit attestation' >&2; exit 65; }
[ "$expected_withdrawal" = "$(printf '%s' "$withdrawal_address" | tr '[:upper:]' '[:lower:]')" ] || { printf '%s\n' 'withdrawal-address confirmation does not match the deposit attestation' >&2; exit 65; }
jq -e --arg key "$public_key" '
  .schema_version == 1 and .source == "private-beacon" and
  .validator_public_key == $key and
  (.payload.syncing.is_syncing == false) and
  (.payload.validator.status == "active_ongoing") and
  (.payload.validator.index | tostring | test("^[0-9]+$"))
' "$private_evidence" >/dev/null || { printf '%s\n' 'private Beacon evidence does not prove an active, synced validator' >&2; exit 65; }

deployment="validator-${validator_set}-client"
signer="validator-${validator_set}-remote-signer"
lease="validator-${validator_set}-primary"
current_set="$(kubectl -n validator-operations get deployment "$deployment" -o jsonpath='{.spec.template.metadata.labels.node-operator\.io/validator-set}')"
[ "$current_set" = "$validator_set" ] || { printf '%s\n' 'rendered client validator-set does not match requested activation' >&2; exit 65; }
replicas="$(kubectl -n validator-operations get deployment "$deployment" -o jsonpath='{.spec.replicas}')"
[ "$replicas" = 0 ] || { printf '%s\n' 'client deployment is not at zero replicas; refuse to take ownership of an existing signer' >&2; exit 65; }
signer_replicas="$(kubectl -n validator-operations get deployment "$signer" -o jsonpath='{.spec.replicas}')"
[ "$signer_replicas" = 1 ] || { printf '%s\n' 'signer is not fenced and running at exactly one replica' >&2; exit 65; }
lease_holder="$(kubectl -n validator-operations get lease "$lease" -o jsonpath='{.spec.holderIdentity}')"
[ -n "$lease_holder" ] || { printf '%s\n' 'signer fence lease has no holder' >&2; exit 65; }
if [ "$dry_run" = true ]; then printf '%s\n' 'PASS: activation gate passed; no workload was scaled because --dry-run was set.'; exit 0; fi
kubectl -n validator-operations scale deployment "$deployment" --replicas=1
printf '%s\n' 'PASS: client scale request submitted. Immediately collect private duty, signer audit, and Kubernetes evidence; do not scale a second client.'
