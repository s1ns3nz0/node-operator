#!/usr/bin/env bash
set -euo pipefail

namespace="${HOODI_NAMESPACE:-node-operator}"
validator_namespace="${VALIDATOR_NAMESPACE:-validator-operations}"
for command in kubectl jq; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 127; }; done

app="$(kubectl -n argocd get application node-operator-client -o json)"
printf '%s' "$app" | jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null || { printf 'UC-1 application is not Synced/Healthy\n' >&2; exit 1; }

for pod in nethermind-execution-0 prysm-beacon-0; do
  ready="$(kubectl -n "$namespace" get pod "$pod" -o json | jq -r '[.status.containerStatuses[]?.ready] | all')"
  [ "$ready" = true ] || { printf 'UC-1 client is not Ready: %s\n' "$pod" >&2; exit 1; }
done

kubectl -n "$validator_namespace" get service hoodi-validator-remote-signer >/dev/null
kubectl -n "$validator_namespace" get lease hoodi-validator-set-primary >/dev/null
endpoints="$(kubectl -n "$validator_namespace" get endpoints hoodi-validator-remote-signer -o json | jq '[.subsets[]?.addresses[]?] | length')"
[ "$endpoints" = 0 ] || { printf 'UC-2 through UC-5 must remain fail-closed until the separately approved signer activation: endpoints=%s\n' "$endpoints" >&2; exit 1; }

printf '%s\n' 'PASS UC-1 is operational; UC-2 through UC-5 custody/signing paths are present and fail-closed.'
