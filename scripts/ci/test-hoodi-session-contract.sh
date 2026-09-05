#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/scripts/ops/hoodi-session.sh"
runbook="$root/docs/operations/cost-optimized-hoodi.md"

fail() { printf 'FAIL Hoodi suspend/resume contract: %s\n' "$*" >&2; exit 1; }

test -f "$script" || fail 'missing Hoodi session operator script'
test -f "$runbook" || fail 'missing Hoodi session runbook'
bash -n "$script"

for required in \
  'Usage: %s {status|start|stop} [--yes]' \
  'requires --yes because it changes runtime capacity' \
  'engine-api-jwt object is absent' \
  'jsonpath='"'"'{.metadata.name}'"'"'' \
  'desiredSize=1' \
  'desiredSize=0' \
  'rollout status statefulset/nethermind-execution' \
  'rollout status statefulset/prysm-beacon' \
  'scale statefulset nethermind-execution prysm-beacon --replicas=0'; do
  grep -Fq "$required" "$script" || fail "missing safety invariant: $required"
done

if grep -Eqi 'jsonpath=.*\.data|base64|kubectl get secret .* -o (yaml|json)' "$script"; then
  fail 'session script could expose a Secret value'
fi

grep -Fq 'scripts/ops/hoodi-session.sh' "$runbook" || fail 'runbook does not point to the operator script'
printf 'PASS Hoodi suspend/resume script preserves non-secret, explicit activation boundaries.\n'
