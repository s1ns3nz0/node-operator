#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
renderer="$root/scripts/ops/render-signer-network-probe.py"
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
key="0x$(printf 'a%.0s' {1..96})"
output="$scratch/probe.json"
PYTHONDONTWRITEBYTECODE=1 python3 "$renderer" --validator-set hoodi-001 --expected-public-key "$key" --output "$output"
jq -e --arg key "$key" '
  .apiVersion == "v1" and .kind == "List" and (.items | type == "array" and length == 2) and
  (.items[0].metadata.name == "signer-probe-direct-hoodi-001") and
  (.items[0].metadata.labels["app.kubernetes.io/component"] == "validator-client") and
  (.items[0].metadata.annotations["node-operator.io/expected-result"] | startswith("must fail")) and
  (.items[1].metadata.name == "signer-probe-control-hoodi-001") and
  (.items[1].metadata.labels["app.kubernetes.io/component"] == "validator-signing-fence") and
  (.items[1].metadata.annotations["node-operator.io/expected-result"] | startswith("must succeed")) and
  all(.items[]; .metadata.namespace == "validator-operations" and .spec.restartPolicy == "Never" and .spec.activeDeadlineSeconds == 120 and .spec.automountServiceAccountToken == false and .spec.enableServiceLinks == false and .spec.securityContext.runAsUser == 65532 and .spec.securityContext.runAsGroup == 65532 and .spec.securityContext.fsGroup == 65532 and .spec.securityContext.seccompProfile.type == "RuntimeDefault" and (.spec.containers | length == 1) and .spec.containers[0].name == "get-only-identity-probe" and .spec.containers[0].image == "106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-signer-identity-probe@sha256:cb359b144ae61a778ac247cf7c6bcb4a210514b1a4da0b825af717ea4231269a" and .spec.containers[0].args == ["--validator-set","hoodi-001","--expected-public-key",$key] and .spec.containers[0].securityContext.readOnlyRootFilesystem == true and .spec.containers[0].securityContext.allowPrivilegeEscalation == false and .spec.containers[0].securityContext.capabilities.drop == ["ALL"] and .spec.containers[0].resources.requests.cpu == "10m" and .spec.containers[0].resources.limits.memory == "64Mi" and .spec.volumes[0].secret.secretName == "validator-hoodi-001-client-tls" and .spec.volumes[0].secret.defaultMode == 288)
' "$output" >/dev/null
for bad_set in hoodi-INVALID hoodi-1234567890123456789012; do
  if PYTHONDONTWRITEBYTECODE=1 python3 "$renderer" --validator-set "$bad_set" --expected-public-key "$key" --output "$scratch/bad.json" >/dev/null 2>&1; then echo "accepted bad set: $bad_set" >&2; exit 1; fi
done
if PYTHONDONTWRITEBYTECODE=1 python3 "$renderer" --validator-set hoodi-001 --expected-public-key "0x$(printf 'g%.0s' {1..96})" --output "$scratch/bad.json" >/dev/null 2>&1; then echo 'accepted malformed public key' >&2; exit 1; fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$renderer" --validator-set hoodi-001 --expected-public-key "$key" --output relative.json >/dev/null 2>&1; then echo 'accepted relative output path' >&2; exit 1; fi
test ! -d "$root/scripts/ops/__pycache__"
printf '%s\n' 'PASS: signer network probe renderer emits bounded GET-only negative/control Pods.'
