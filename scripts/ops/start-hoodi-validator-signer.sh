#!/usr/bin/env bash
set -euo pipefail

usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> [--dry-run]" >&2; exit 64; }
validator_set=''; dry_run=false
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) validator_set="${2:-}"; shift 2 ;; --dry-run) dry_run=true; shift ;; *) usage ;; esac; done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
for command in kubectl date jq; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
namespace=validator-operations
signer="validator-${validator_set}-remote-signer"
lease="validator-${validator_set}-primary"
replicas="$(kubectl -n "$namespace" get deployment "$signer" -o jsonpath='{.spec.replicas}')"
[ "$replicas" = 0 ] || { printf '%s\n' 'signer is not at zero replicas; refuse concurrent ownership' >&2; exit 65; }
holder="$(kubectl -n "$namespace" get lease "$lease" -o jsonpath='{.spec.holderIdentity}')"
[ -z "$holder" ] || { printf '%s\n' 'fence lease already has a holder; refuse signer start' >&2; exit 65; }
if [ "$dry_run" = true ]; then printf '%s\n' 'PASS: signer start gate passed; no lease or workload changed.'; exit 0; fi
# coordination.k8s.io Lease uses MicroTime for acquire/renew timestamps.
# Kubernetes rejects a whole-second RFC3339 value even in a JSON Patch, so
# emit the required six fractional digits deterministically on BSD and GNU date.
now="$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)"
holder="${signer}-$(date -u +%Y%m%d%H%M%S)"
# JSON Patch test makes the empty-lease claim atomic; a concurrent claimant
# fails rather than replacing an existing holder.
patch="$(jq -cn --arg holder "$holder" --arg now "$now" '[{op:"test",path:"/spec/holderIdentity",value:""},{op:"replace",path:"/spec/holderIdentity",value:$holder},{op:"add",path:"/spec/acquireTime",value:$now},{op:"add",path:"/spec/renewTime",value:$now}]')"
kubectl -n "$namespace" patch lease "$lease" --type=json -p "$patch"
kubectl -n "$namespace" scale deployment "$signer" --replicas=1
printf '%s\n' 'PASS: signer fence lease acquired and scale request submitted. Start the client only through activate-hoodi-validator-client.sh.'
