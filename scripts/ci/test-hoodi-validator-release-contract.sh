#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/release/hoodi-validator-release.sh"
scratch="$(mktemp -d /private/tmp/node-operator-validator-release.XXXXXX)"
bundle="$scratch/bundle"; inputs="$scratch/inputs"; trace="$scratch/trace"
mkdir -p "$bundle/source/scripts/release" "$bundle/source/scripts/ops" "$inputs/zero-resource" "$inputs/validator-deployment"
printf '{}' > "$bundle/bundle-manifest.json"
cat > "$bundle/source/scripts/release/node-operator-release.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'release %s\n' "$*" >> "$TRACE"
if [ "${1:-}:${2:-}" = 'zero:apply' ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in --work-dir) work_dir="$2"; shift 2 ;; *) shift ;; esac
  done
  mkdir -p "$work_dir"
  jq -n '{schema_version:"v1",aws_account_id:"106760547719"}' > "$work_dir/ops-access-handoff.json"
fi
SCRIPT
cat > "$bundle/source/scripts/release/stage-hoodi-validator-deployment.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'stage %s\n' "$*" >> "$TRACE"
if [ "${1:-}" = verify ] && [ ! -f "$TRACE.staged" ]; then exit 3; fi
if [ "${1:-}" = apply ]; then : > "$TRACE.staged"; fi
SCRIPT
cat > "$bundle/source/scripts/release/prepare-ops-access-inputs.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'ops %s\n' "$*" >> "$TRACE"
while [ "$#" -gt 0 ]; do
  case "$1" in --handoff) handoff="$2"; shift 2 ;; --output-dir) output_dir="$2"; shift 2 ;; *) shift ;; esac
done
mkdir -p "$output_dir"
printf '{}' > "$output_dir/ops-access.tfvars.json"
printf '{}' > "$output_dir/ops-access.backend.hcl"
jq -n --arg handoff "$handoff" --arg config "$output_dir/ops-access.tfvars.json" --arg backend "$output_dir/ops-access.backend.hcl" '{schema_version:1,ops_access_handoff:$handoff,config:$config,backend_config:$backend}' > "$output_dir/ops-access-inputs.json"
SCRIPT
cat > "$bundle/source/scripts/release/node-operator-ops-access.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'ops-access %s\n' "$*" >> "$TRACE"
operation="$1"; shift
while [ "$#" -gt 0 ]; do
  case "$1" in --plan-file) plan_file="$2"; shift 2 ;; --session-handoff) session_handoff="$2"; shift 2 ;; *) shift ;; esac
done
if [ "$operation" = plan ]; then : > "$plan_file"; fi
if [ "$operation" = apply ]; then jq -n '{schema_version:1,aws_region:"ap-northeast-2",cluster_name:"hoodi-release-001",ssm_ops_instance_id:"i-0123456789abcdef0"}' > "$session_handoff"; fi
SCRIPT
for command in with-private-eks.sh with-private-vault.sh recover-and-bootstrap-hoodi-validator-runtime-vault.sh recover-and-onboard-hoodi-validator-keystore.sh provision-hoodi-transport-tls.sh start-hoodi-validator-signer.sh collect-hoodi-signer-public-key-evidence.sh observe-private-hoodi-validator.sh activate-hoodi-validator-client.sh; do
  cat > "$bundle/source/scripts/ops/$command" <<'SCRIPT'
#!/usr/bin/env bash
printf 'activation %s\n' "$*" >> "$TRACE"
SCRIPT
  chmod 700 "$bundle/source/scripts/ops/$command"
done
chmod 700 "$bundle/source/scripts/release/node-operator-release.sh" "$bundle/source/scripts/release/stage-hoodi-validator-deployment.sh" "$bundle/source/scripts/release/prepare-ops-access-inputs.sh" "$bundle/source/scripts/release/node-operator-ops-access.sh"
jq -n --arg zero "$inputs/zero-resource/zero-resource-inputs.json" --arg validator "$inputs/validator-deployment/validator-deployment-handoff.json" '{schema_version:1,network:"hoodi",aws_account_id:"106760547719",aws_region:"ap-northeast-2",validator_set:"hoodi-release-001",zero_resource_inputs:$zero,validator_deployment_handoff:$validator,required_checkpoints:[1,2,3,4,5,6]}' > "$inputs/hoodi-zero-release-inputs.json"
jq -n '{schema_version:1,aws_account_id:"106760547719",aws_region:"ap-northeast-2"}' > "$inputs/zero-resource/zero-resource-inputs.json"
jq -n '{schema_version:1,network:"hoodi",aws_account_id:"106760547719",aws_region:"ap-northeast-2",validator_set:"hoodi-release-001",validator_public_key:("0x" + ("a" * 96)),staged_client_replicas:0,staged_fence_replicas:0}' > "$inputs/validator-deployment/validator-deployment-handoff.json"
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
rg -F 'deploy apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json' "$script" >/dev/null
rg -F '"entrypoint": "source/scripts/release/hoodi-validator-release.sh"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"deploy apply"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"interactive custody"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"custody apply"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"evidence signer"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"evidence beacon"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"activate apply"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F '"stage verify"' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F 'activate apply --bundle-root DIRECTORY' "$script" >/dev/null
rg -F 'interactive custody --bundle-root DIRECTORY' "$script" >/dev/null
rg -F 'evidence signer --bundle-root DIRECTORY' "$script" >/dev/null
rg -F 'evidence beacon --bundle-root DIRECTORY' "$script" >/dev/null
rg -F 'NEXT: run %s interactive custody' "$script" >/dev/null
rg -F 'validator private key or keystore' "$root/release/hoodi-release-contract.json" >/dev/null
rg -F 'infrastructure, isolated private-EKS SSM access, and zero-replica validator staging are deployed' "$script" >/dev/null
rg -F 'deploy checkpoint contains an invalid ops-access plan digest' "$script" >/dev/null
deploy_work="$scratch/deploy-work"; deploy_session="$scratch/deploy-session.json"
TRACE="$trace" "$script" deploy apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --work-dir "$deploy_work" --private-eks-session-handoff "$deploy_session" --allow-create >/dev/null
rg -F "release zero apply --bundle-root $bundle --inputs $inputs/zero-resource/zero-resource-inputs.json --work-dir $deploy_work" "$trace" >/dev/null
rg -F "ops --handoff $deploy_work/ops-access-handoff.json --output-dir $deploy_work/ops-access-inputs" "$trace" >/dev/null
rg -F "ops-access plan --root $bundle/source --inputs $deploy_work/ops-access-inputs/ops-access-inputs.json --plan-file $deploy_work/ops-access.tfplan --allow-create" "$trace" >/dev/null
rg -F "ops-access apply --root $bundle/source --inputs $deploy_work/ops-access-inputs/ops-access-inputs.json --plan-file $deploy_work/ops-access.tfplan" "$trace" >/dev/null
rg -F "stage verify --handoff $inputs/validator-deployment/validator-deployment-handoff.json --private-eks-session-handoff $deploy_session" "$trace" >/dev/null
rg -F "stage apply --handoff $inputs/validator-deployment/validator-deployment-handoff.json --private-eks-session-handoff $deploy_session" "$trace" >/dev/null
jq -e '.ssm_ops_instance_id == "i-0123456789abcdef0"' "$deploy_session" >/dev/null
keystore_dir="$scratch/keystore"; mkdir -m 700 "$keystore_dir"; printf '{}' > "$keystore_dir/keystore-test.json"
ceremony_dir="$scratch/ceremony"
TRACE="$trace" "$script" custody apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$deploy_session" --keystore-dir "$keystore_dir" --ceremony-dir "$ceremony_dir" >/dev/null
test -d "$ceremony_dir"
rg -F "activation -- env AWS_REGION=ap-northeast-2 EKS_CLUSTER_NAME=hoodi-release-001 SSM_OPS_INSTANCE_ID=i-0123456789abcdef0 PRIVATE_VAULT_SESSION=1 $bundle/source/scripts/ops/recover-and-bootstrap-hoodi-validator-runtime-vault.sh --validator-set hoodi-release-001" "$trace" >/dev/null
rg -F "$bundle/source/scripts/ops/recover-and-onboard-hoodi-validator-keystore.sh --validator-set hoodi-release-001 --keystore-dir $keystore_dir --signer-ca-output $ceremony_dir/signer-ca.crt --known-clients-output $ceremony_dir/known-clients.txt" "$trace" >/dev/null
rg -F "kubectl -n validator-operations create configmap validator-hoodi-release-001-known-clients --from-file=known-clients=$ceremony_dir/known-clients.txt" "$trace" >/dev/null
signer_evidence_dir="$scratch/signer-evidence"
TRACE="$trace" "$script" evidence signer --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$deploy_session" --output-dir "$signer_evidence_dir" >/dev/null
rg -F "activation -- env PRIVATE_EKS_SESSION=1 AWS_REGION=ap-northeast-2 EKS_CLUSTER_NAME=hoodi-release-001 SSM_OPS_INSTANCE_ID=i-0123456789abcdef0 $bundle/source/scripts/ops/start-hoodi-validator-signer.sh --validator-set hoodi-release-001" "$trace" >/dev/null
rg -F "$bundle/source/scripts/ops/collect-hoodi-signer-public-key-evidence.sh --validator-set hoodi-release-001 --validator-public-key 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --output-dir $signer_evidence_dir" "$trace" >/dev/null
beacon_evidence_dir="$scratch/beacon-evidence"
TRACE="$trace" "$script" evidence beacon --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$deploy_session" --output-dir "$beacon_evidence_dir" >/dev/null
rg -F "$bundle/source/scripts/ops/observe-private-hoodi-validator.sh --validator-set hoodi-release-001 --validator-public-key 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --correlation-id" "$trace" >/dev/null
rg -F -- "--output-dir $beacon_evidence_dir" "$trace" >/dev/null
for evidence in deposit-attestation public-deposit private-evidence signer-evidence; do printf '{}' > "$scratch/$evidence.json"; done
TRACE="$trace" "$script" activate apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$deploy_session" --deposit-attestation "$scratch/deposit-attestation.json" --public-deposit-verification "$scratch/public-deposit.json" --private-evidence "$scratch/private-evidence.json" --signer-evidence "$scratch/signer-evidence.json" --confirm-public-key 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm-withdrawal-address 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
rg -F "$bundle/source/scripts/ops/activate-hoodi-validator-client.sh --validator-set hoodi-release-001" "$trace" >/dev/null
bad_session="$scratch/bad-session.json"; jq '.cluster_name = "INVALID"' "$deploy_session" > "$bad_session"
if TRACE="$trace" "$script" activate apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --private-eks-session-handoff "$bad_session" --deposit-attestation "$scratch/deposit-attestation.json" --public-deposit-verification "$scratch/public-deposit.json" --private-evidence "$scratch/private-evidence.json" --signer-evidence "$scratch/signer-evidence.json" --confirm-public-key 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm-withdrawal-address 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null 2>&1; then
  printf '%s\n' 'activation unexpectedly accepted an invalid session handoff' >&2; exit 1
fi
before_apply_count="$(rg -c '^ops-access apply ' "$trace")"
TRACE="$trace" "$script" deploy apply --bundle-root "$bundle" --inputs "$inputs/hoodi-zero-release-inputs.json" --work-dir "$deploy_work" --private-eks-session-handoff "$deploy_session" --allow-create >/dev/null
[ "$(rg -c '^ops-access apply ' "$trace")" = "$before_apply_count" ] || { printf '%s\n' 'deploy resume unexpectedly re-applied ops access' >&2; exit 1; }
stage_apply_count="$(rg -c '^stage apply ' "$trace")"
[ "$stage_apply_count" = 1 ] || { printf '%s\n' 'deploy resume unexpectedly re-applied existing staged workloads' >&2; exit 1; }
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
