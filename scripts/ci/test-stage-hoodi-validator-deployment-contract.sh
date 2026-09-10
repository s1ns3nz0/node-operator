#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/release/stage-hoodi-validator-deployment.sh"
scratch="$(mktemp -d /private/tmp/node-operator-stage-validator.XXXXXX)"
tools="$scratch/tools"; mkdir "$tools"
handoff_dir="$scratch/handoff"; mkdir -m 700 "$handoff_dir"
runtime="$handoff_dir/runtime.yaml"; client="$handoff_dir/client-and-fence.yaml"; handoff="$handoff_dir/validator-deployment-handoff.json"

printf '%s\n' 'apiVersion: v1
kind: ConfigMap
metadata: {name: runtime, namespace: validator-operations}' > "$runtime"
printf '%s\n' 'apiVersion: v1
kind: ConfigMap
metadata: {name: client, namespace: validator-operations}' > "$client"
jq -n --arg runtime "$runtime" --arg client "$client" '{schema_version:1,network:"hoodi",validator_set:"hoodi-stage-001",aws_account_id:"106760547719",runtime_manifest:$runtime,client_manifest:$client,staged_client_replicas:0,staged_fence_replicas:0,next_steps:["bounded"]}' > "$handoff"
chmod 600 "$handoff"

cat > "$tools/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$KUBECTL_TRACE"
case " $* " in
  *' apply '*' --dry-run=server '*) exit 0 ;;
  *' get '*) exit 1 ;;
  *) printf 'unexpected kubectl call: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod 700 "$tools/kubectl"

KUBECTL_TRACE="$scratch/kubectl.trace" PATH="$tools:$PATH" PRIVATE_EKS_SESSION=1 "$script" plan --handoff "$handoff" >/dev/null
rg -F -- '--server-side --field-manager=node-operator-release-stage --dry-run=server' "$scratch/kubectl.trace" >/dev/null
if KUBECTL_TRACE="$scratch/secret.trace" PATH="$tools:$PATH" PRIVATE_EKS_SESSION=1 "$script" plan --handoff /dev/null >/dev/null 2>&1; then
  printf '%s\n' 'unsafe handoff unexpectedly accepted' >&2
  exit 1
fi
printf '%s\n' 'PASS: staging command validates a bounded handoff and performs server-side dry-run before apply.'
