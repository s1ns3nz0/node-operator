#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/release/hoodi-validator-release.sh"
scratch="$(mktemp -d /private/tmp/node-operator-validator-release.XXXXXX)"
bundle="$scratch/bundle"; inputs="$scratch/inputs"; trace="$scratch/trace"
mkdir -p "$bundle/source/scripts/release" "$inputs/zero-resource" "$inputs/validator-deployment"
printf '{}' > "$bundle/bundle-manifest.json"
cat > "$bundle/source/scripts/release/node-operator-release.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'release %s\n' "$*" >> "$TRACE"
SCRIPT
cat > "$bundle/source/scripts/release/stage-hoodi-validator-deployment.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'stage %s\n' "$*" >> "$TRACE"
SCRIPT
cat > "$bundle/source/scripts/release/prepare-ops-access-inputs.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'ops %s\n' "$*" >> "$TRACE"
SCRIPT
cat > "$bundle/source/scripts/release/node-operator-ops-access.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'ops-access %s\n' "$*" >> "$TRACE"
SCRIPT
chmod 700 "$bundle/source/scripts/release/node-operator-release.sh" "$bundle/source/scripts/release/stage-hoodi-validator-deployment.sh" "$bundle/source/scripts/release/prepare-ops-access-inputs.sh" "$bundle/source/scripts/release/node-operator-ops-access.sh"
jq -n --arg zero "$inputs/zero-resource/zero-resource-inputs.json" --arg validator "$inputs/validator-deployment/validator-deployment-handoff.json" '{schema_version:1,network:"hoodi",aws_account_id:"106760547719",aws_region:"ap-northeast-2",validator_set:"hoodi-release-001",zero_resource_inputs:$zero,validator_deployment_handoff:$validator,required_checkpoints:[1,2,3,4,5,6]}' > "$inputs/hoodi-zero-release-inputs.json"
jq -n '{schema_version:1,aws_account_id:"106760547719",aws_region:"ap-northeast-2"}' > "$inputs/zero-resource/zero-resource-inputs.json"
jq -n '{schema_version:1,network:"hoodi",aws_account_id:"106760547719",aws_region:"ap-northeast-2",staged_client_replicas:0,staged_fence_replicas:0}' > "$inputs/validator-deployment/validator-deployment-handoff.json"
if "$script" interactive prepare --bundle-root "$bundle" --output-dir "$scratch/interactive" </dev/null >/dev/null 2>&1; then
  printf '%s\n' 'interactive preparation unexpectedly accepted a non-terminal input stream' >&2; exit 1
fi
TRACE="$trace" "$script" infrastructure apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --work-dir "$scratch/work" >/dev/null
rg -F "release verify --bundle-root $bundle" "$trace" >/dev/null
rg -F "release zero apply --bundle-root $bundle --inputs $inputs/zero-resource/zero-resource-inputs.json --work-dir $scratch/work" "$trace" >/dev/null
mkdir -p "$scratch/zero"; printf '{}' > "$scratch/zero/ops-access-handoff.json"
TRACE="$trace" "$script" ops-inputs prepare --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --zero-work-dir "$scratch/zero" --output-dir "$scratch/ops" >/dev/null
rg -F "ops --handoff $scratch/zero/ops-access-handoff.json --output-dir $scratch/ops" "$trace" >/dev/null
mkdir -p "$scratch/ops"
printf '{}' > "$scratch/ops/ops-access.tfvars.json"; printf '{}' > "$scratch/ops/ops-access.backend.hcl"
jq -n --arg handoff "$scratch/zero/ops-access-handoff.json" --arg config "$scratch/ops/ops-access.tfvars.json" --arg backend "$scratch/ops/ops-access.backend.hcl" '{schema_version:1,ops_access_handoff:$handoff,config:$config,backend_config:$backend}' > "$scratch/ops/ops-access-inputs.json"
jq -n '{schema_version:"v1",aws_account_id:"106760547719"}' > "$scratch/zero/ops-access-handoff.json"
mkdir -m 700 "$scratch/plans"
TRACE="$trace" "$script" ops-access plan --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --ops-inputs "$scratch/ops/ops-access-inputs.json" --plan-file "$scratch/plans/ops.tfplan" --allow-create >/dev/null
rg -F "ops-access plan --root $bundle/source --inputs $scratch/ops/ops-access-inputs.json --plan-file $scratch/plans/ops.tfplan --allow-create" "$trace" >/dev/null
session="$scratch/session.json"; jq -n '{schema_version:1,aws_region:"ap-northeast-2",cluster_name:"node-operator",ssm_ops_instance_id:"i-0123456789abcdef0"}' > "$session"
if TRACE="$trace" "$script" ops-access apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --ops-inputs "$scratch/ops/ops-access-inputs.json" --plan-file "$scratch/plans/ops.tfplan" >/dev/null 2>&1; then
  printf '%s\n' 'ops-access apply unexpectedly accepted without a session handoff' >&2; exit 1
fi
TRACE="$trace" "$script" stage plan --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$session" >/dev/null
rg -F "stage plan --handoff $inputs/validator-deployment/validator-deployment-handoff.json --private-eks-session-handoff $session" "$trace" >/dev/null
jq '.aws_account_id = "999999999999"' "$inputs/validator-deployment/validator-deployment-handoff.json" > "$scratch/mismatch.json"
mv "$scratch/mismatch.json" "$inputs/validator-deployment/validator-deployment-handoff.json"
if TRACE="$trace" "$script" stage plan --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$session" >/dev/null 2>&1; then
  printf '%s\n' 'mismatched validator account unexpectedly accepted' >&2; exit 1
fi
printf '%s\n' 'PASS: Hoodi release command binds each non-secret phase to one validated input contract.'
