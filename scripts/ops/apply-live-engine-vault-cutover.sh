#!/usr/bin/env bash
set -euo pipefail
umask 077

# Applies only the Engine pair after migration evidence exists. It updates the
# immutable Argo chart revision, waits for desired templates, then restarts the
# OnDelete StatefulSets one at a time. It never deletes the legacy JWT Secret.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { printf 'Usage: %s --chart-version 0.1.N --chart-digest sha256:HEX --migration-evidence <absolute-json> --preflight-evidence <absolute-json> --evidence-output <new-absolute-json> --execute\n' "${0##*/}" >&2; exit 64; }
version=''; digest=''; migration=''; preflight=''; evidence=''; execute=false
while [ "$#" -gt 0 ]; do case "$1" in
  --chart-version) version="${2:-}"; shift 2;; --chart-digest) digest="${2:-}"; shift 2;; --migration-evidence) migration="${2:-}"; shift 2;; --preflight-evidence) preflight="${2:-}"; shift 2;; --evidence-output) evidence="${2:-}"; shift 2;; --execute) execute=true; shift;; *) usage;;
esac; done
[[ "$version" =~ ^0\.1\.[0-9]+$ ]] && [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || usage
case "$migration:$preflight:$evidence" in /*:/*:/*) ;; *) usage;; esac
[ "$execute" = true ] || usage
[ -f "$migration" ] && [ ! -L "$migration" ] && [ -f "$preflight" ] && [ ! -L "$preflight" ] && [ ! -e "$evidence" ] && [ ! -L "$evidence" ] || { printf '%s\n' 'invalid evidence paths' >&2; exit 65; }
if [ "${PRIVATE_EKS_SESSION:-}" != 1 ]; then exec "$dir/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 "$0" --chart-version "$version" --chart-digest "$digest" --migration-evidence "$migration" --preflight-evidence "$preflight" --evidence-output "$evidence" --execute; fi
for command in kubectl jq date mkdir sleep; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
jq -e '.operation == "live-runtime-secret-migration" and .source_secrets_retained == true and .secret_values_emitted == false' "$migration" >/dev/null
jq -e '.operation == "live-vault-cutover-preflight" and .phase == "baseline" and .engine_pair_ready == true and .vault_injector_ready == true' "$preflight" >/dev/null

app_ns='argocd'; app='node-operator-client'; namespace='node-operator'
before="$(kubectl -n "$app_ns" get application "$app" -o json)"
jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' <<<"$before" >/dev/null || { printf '%s\n' 'Argo Application is not healthy before cutover' >&2; exit 65; }
kubectl -n "$app_ns" patch application "$app" --type merge -p "{\"metadata\":{\"annotations\":{\"node-operator.io/approved-chart-digest\":\"${digest}\"}},\"spec\":{\"source\":{\"targetRevision\":\"${version}\"}}}" >/dev/null

ready=false
for _ in $(seq 1 120); do
  app_json="$(kubectl -n "$app_ns" get application "$app" -o json)"
  if jq -e --arg version "$version" '.spec.source.targetRevision == $version and .status.sync.status == "Synced" and .status.health.status == "Healthy" and .status.sync.revision == $version' <<<"$app_json" >/dev/null; then ready=true; break; fi
  sleep 5
done
[ "$ready" = true ] || { printf '%s\n' 'Argo did not converge to requested immutable chart revision' >&2; exit 70; }

for stateful in nethermind-execution prysm-beacon; do
  template="$(kubectl -n "$namespace" get statefulset "$stateful" -o json)"
  jq -e '.spec.template.metadata.annotations["vault.hashicorp.com/agent-inject"] == "true" and .spec.template.metadata.annotations["vault.hashicorp.com/agent-inject-secret-engine.jwt"] == "kv/data/nodes/hoodi/engine-api-jwt"' <<<"$template" >/dev/null || { printf 'Vault injection template missing: %s\n' "$stateful" >&2; exit 65; }
  jq -e '[.spec.template.spec.volumes[]? | select(.secret.secretName == "engine-api-jwt")] | length == 0' <<<"$template" >/dev/null || { printf 'legacy JWT Secret remains mounted: %s\n' "$stateful" >&2; exit 65; }
done

for stateful in nethermind-execution prysm-beacon; do
  kubectl -n "$namespace" delete pod "${stateful}-0" --wait=true >/dev/null
  kubectl -n "$namespace" rollout status "statefulset/${stateful}" --timeout=20m >/dev/null
  pod="$(kubectl -n "$namespace" get pod "${stateful}-0" -o json)"
  jq -e '[.status.initContainerStatuses[]? | select(.name == "vault-agent-init" and .state.terminated.exitCode == 0)] | length == 1' <<<"$pod" >/dev/null || { printf 'Vault Agent init did not succeed: %s\n' "$stateful" >&2; exit 70; }
done

mkdir -p "$(dirname "$evidence")"
jq -n --arg version "$version" --arg digest "$digest" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema_version:1,operation:"live-engine-vault-cutover",completed_at_utc:$at,argocd_chart_version:$version,argocd_chart_digest:$digest,nethermind_restarted:true,prysm_restarted:true,vault_agent_init_succeeded:true,legacy_engine_jwt_secret_retained:true,secret_values_emitted:false}' > "$evidence"
chmod 600 "$evidence"
printf 'PASS: Engine pair cut over to Vault-injected JWT with one-at-a-time OnDelete restarts. Legacy Secret remains until final cleanup. Evidence: %s\n' "$evidence"
