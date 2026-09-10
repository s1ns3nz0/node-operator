#!/usr/bin/env bash
set -euo pipefail
umask 077

# Drives only non-secret release boundaries from the single preparation
# handoff. Vault recovery, custody, GitOps publication, and activation remain
# separate ceremonies and cannot be smuggled through this entrypoint.
usage() {
  cat >&2 <<'USAGE'
usage:
  hoodi-validator-release.sh verify --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json
  hoodi-validator-release.sh interactive prepare --bundle-root DIRECTORY --output-dir /new-absolute-directory [--aws-region ap-northeast-1|ap-northeast-2]
  hoodi-validator-release.sh infrastructure apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --work-dir /new-absolute-directory
  hoodi-validator-release.sh ops-inputs prepare --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --zero-work-dir /absolute/zero-work-dir --output-dir /new-absolute-directory
  hoodi-validator-release.sh ops-access plan|apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --ops-inputs /absolute/ops-access-inputs.json --plan-file /absolute/private.tfplan [--expected-sha SHA256] [--allow-create] [--private-eks-session-handoff /absolute/session.json]
  hoodi-validator-release.sh stage plan|apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json
USAGE
  exit 64
}

command_name="${1:-}"; [ -n "$command_name" ] || usage
shift
operation=''; bundle_root=''; inputs=''; work_dir=''; session_handoff=''; output_dir=''; ops_inputs=''; plan_file=''; expected_sha=''; aws_region='ap-northeast-2'; allow_create=false
case "$command_name" in
  interactive|infrastructure|ops-inputs|ops-access|stage)
    [ "$#" -gt 0 ] || usage
    operation="$1"
    shift
    ;;
  verify) ;;
  *) usage ;;
esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root) bundle_root="${2:-}"; shift 2 ;;
    --inputs) inputs="${2:-}"; shift 2 ;;
    --work-dir) work_dir="${2:-}"; shift 2 ;;
    --zero-work-dir) work_dir="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    --ops-inputs) ops_inputs="${2:-}"; shift 2 ;;
    --plan-file) plan_file="${2:-}"; shift 2 ;;
    --expected-sha) expected_sha="${2:-}"; shift 2 ;;
    --aws-region) aws_region="${2:-}"; shift 2 ;;
    --allow-create) allow_create=true; shift ;;
    --private-eks-session-handoff) session_handoff="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [ "$command_name" = interactive ]; then
  [ "$operation" = prepare ] && [ -n "$bundle_root$output_dir" ] && [ -z "$inputs$work_dir$session_handoff$ops_inputs$plan_file$expected_sha" ] && [ "$allow_create" = false ] || usage
  case "$bundle_root:$output_dir" in */*:/*) ;; *) usage ;; esac
  [ -t 0 ] && [ -t 1 ] || { printf '%s\n' 'interactive preparation requires a terminal' >&2; exit 69; }
  command -v aws >/dev/null 2>&1 || { printf '%s\n' 'missing command: aws' >&2; exit 69; }
  case "$aws_region" in ap-northeast-1|ap-northeast-2) ;; *) printf '%s\n' 'aws region must be ap-northeast-1 or ap-northeast-2' >&2; exit 64 ;; esac
  identity="$(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN aws sts get-caller-identity --output json)"
  account="$(jq -er '.Account' <<<"$identity")"
  [[ "$account" =~ ^[0-9]{12}$ ]] || { printf '%s\n' 'current AWS identity did not return a valid account' >&2; exit 65; }
  prompt() { local label="$1" value; printf '%s: ' "$label" >&2; IFS= read -r value; printf '%s' "$value"; }
  validator_set="$(prompt 'Validator set (hoodi-...)')"
  validator_key="$(prompt 'Validator public key (0x...)')"
  withdrawal_address="$(prompt 'Withdrawal address (0x...)')"
  web3signer_image="$(prompt 'Approved Web3Signer private ECR digest')"
  postgres_image="$(prompt 'Approved PostgreSQL private ECR digest')"
  prysm_image="$(prompt 'Approved Prysm validator private ECR digest')"
  fence_image="$(prompt 'Approved signing-fence private ECR digest')"
  kubernetes_api_cidr="$(prompt 'Operator public IPv4 /32')"
  availability_zones=()
  while IFS= read -r zone; do availability_zones+=("$zone"); done < <(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN aws ec2 describe-availability-zones --region "$aws_region" --filters Name=state,Values=available --query 'AvailabilityZones[].ZoneName' --output text | tr '\t' '\n' | sort | head -n 2)
  [ "${#availability_zones[@]}" -eq 2 ] || { printf '%s\n' 'could not discover two available zones in the selected Region' >&2; exit 65; }
  backend_args=()
  identity_arn="$(jq -er '.Arn' <<<"$identity")"
  case "$identity_arn" in
    "arn:aws:iam::${account}:user/"*)
      backend_role="$(prompt 'Terraform backend IAM role ARN (same account)')"
      backend_args=(--backend-principal-arn "$backend_role")
      ;;
  esac
  "$bundle_root/source/scripts/release/prepare-hoodi-zero-release-inputs.sh" \
    --aws-account-id "$account" --aws-region "$aws_region" --availability-zone "${availability_zones[0]}" --availability-zone "${availability_zones[1]}" --validator-set "$validator_set" --validator-public-key "$validator_key" \
    --withdrawal-address "$withdrawal_address" --web3signer-image "$web3signer_image" \
    --postgres-image "$postgres_image" --prysm-validator-image "$prysm_image" \
    --signing-fence-image "$fence_image" --kubernetes-api-cidr "$kubernetes_api_cidr" --output-dir "$output_dir" "${backend_args[@]}"
  printf 'PASS: initial release values are prepared. Continue with infrastructure apply using %s/hoodi-zero-release-inputs.json.\n' "$output_dir"
  exit 0
fi

case "$bundle_root:$inputs" in */*:/*) ;; *) usage ;; esac
[ -d "$bundle_root/source" ] && [ -f "$bundle_root/bundle-manifest.json" ] || { printf '%s\n' 'bundle root is not a verified release layout' >&2; exit 65; }
[ -f "$inputs" ] && [ ! -L "$inputs" ] || { printf '%s\n' 'inputs must name a regular file' >&2; exit 65; }
command -v jq >/dev/null 2>&1 || { printf '%s\n' 'missing command: jq' >&2; exit 69; }

input_parent="$(cd "$(dirname "$inputs")" && pwd -P)"
zero_inputs="$input_parent/zero-resource/zero-resource-inputs.json"
validator_handoff="$input_parent/validator-deployment/validator-deployment-handoff.json"
jq -e --arg zero "$zero_inputs" --arg validator "$validator_handoff" '
  .schema_version == 1 and .network == "hoodi" and
  (.aws_account_id | test("^[0-9]{12}$")) and
  (.validator_set | test("^hoodi-[a-z0-9][a-z0-9-]*$")) and
  (.aws_region | test("^ap-northeast-(1|2)$")) and .zero_resource_inputs == $zero and .validator_deployment_handoff == $validator and
  (.required_checkpoints | type == "array" and length == 6)
' "$inputs" >/dev/null || { printf '%s\n' 'inputs are not a bounded Hoodi zero-release contract' >&2; exit 65; }
[ -f "$zero_inputs" ] && [ ! -L "$zero_inputs" ] && [ -f "$validator_handoff" ] && [ ! -L "$validator_handoff" ] || { printf '%s\n' 'release contract references missing or unsafe inputs' >&2; exit 65; }
account="$(jq -er '.aws_account_id' "$inputs")"
input_region="$(jq -er '.aws_region' "$inputs")"
jq -e --arg account "$account" --arg region "$input_region" '.schema_version == 1 and .aws_account_id == $account and .aws_region == $region' "$zero_inputs" >/dev/null || { printf '%s\n' 'zero-resource input account or region does not match the release contract' >&2; exit 65; }
jq -e --arg account "$account" --arg region "$input_region" '.schema_version == 1 and .network == "hoodi" and .aws_account_id == $account and .aws_region == $region and .staged_client_replicas == 0 and .staged_fence_replicas == 0' "$validator_handoff" >/dev/null || { printf '%s\n' 'validator handoff does not match the release contract or is not fenced' >&2; exit 65; }

release_dir="$bundle_root/source/scripts/release"
"$release_dir/node-operator-release.sh" verify --bundle-root "$bundle_root"
case "$command_name" in
  verify)
    [ -z "$operation$work_dir$session_handoff" ] || usage
    printf 'PASS: Hoodi zero-release input contract is consistent and remains non-secret.\n'
    ;;
  infrastructure)
    [ "$operation" = apply ] && [ -n "$work_dir" ] && [ -z "$session_handoff$output_dir" ] || usage
    "$release_dir/node-operator-release.sh" zero apply --bundle-root "$bundle_root" --inputs "$zero_inputs" --work-dir "$work_dir"
    ;;
  ops-inputs)
    [ "$operation" = prepare ] && [ -n "$work_dir$output_dir" ] && [ -z "$session_handoff" ] || usage
    case "$work_dir:$output_dir" in /*:/*) ;; *) usage ;; esac
    "$release_dir/prepare-ops-access-inputs.sh" --handoff "$work_dir/ops-access-handoff.json" --output-dir "$output_dir"
    ;;
  ops-access)
    [ "$operation" = plan ] || [ "$operation" = apply ] || usage
    case "$ops_inputs:$plan_file" in /*:/*) ;; *) usage ;; esac
    if [ "$operation" = apply ]; then
      [ -n "$session_handoff" ] || { printf '%s\n' 'ops-access apply must write --private-eks-session-handoff for the next release phase' >&2; exit 64; }
    else
      [ -z "$session_handoff" ] || { printf '%s\n' 'ops-access plan must not create a private EKS session handoff' >&2; exit 64; }
    fi
    [ -f "$ops_inputs" ] && [ ! -L "$ops_inputs" ] || { printf '%s\n' 'ops inputs must be a regular file' >&2; exit 65; }
    ops_parent="$(cd "$(dirname "$ops_inputs")" && pwd -P)"
    ops_handoff="$(jq -er '.ops_access_handoff' "$ops_inputs")" || { printf '%s\n' 'ops inputs lack a source handoff' >&2; exit 65; }
    [ -f "$ops_handoff" ] && [ ! -L "$ops_handoff" ] || { printf '%s\n' 'ops source handoff is unsafe' >&2; exit 65; }
    jq -e --arg account "$account" --arg handoff "$ops_handoff" --arg config "$ops_parent/ops-access.tfvars.json" --arg backend "$ops_parent/ops-access.backend.hcl" '
      .schema_version == 1 and .ops_access_handoff == $handoff and .config == $config and .backend_config == $backend
    ' "$ops_inputs" >/dev/null || { printf '%s\n' 'ops input paths are not bounded' >&2; exit 65; }
    jq -e --arg account "$account" '.schema_version == "v1" and .aws_account_id == $account' "$ops_handoff" >/dev/null || { printf '%s\n' 'ops access account does not match the release contract' >&2; exit 65; }
    ops_args=("$operation" --root "$bundle_root/source" --inputs "$ops_inputs" --plan-file "$plan_file")
    [ -z "$expected_sha" ] || ops_args+=(--expected-sha "$expected_sha")
    [ "$allow_create" = false ] || ops_args+=(--allow-create)
    [ -z "$session_handoff" ] || ops_args+=(--session-handoff "$session_handoff")
    "$release_dir/node-operator-ops-access.sh" "${ops_args[@]}"
    ;;
  stage)
    [ "$operation" = plan ] || [ "$operation" = apply ] || usage
    [ -n "$session_handoff" ] && [ -z "$work_dir$output_dir" ] || usage
    "$release_dir/stage-hoodi-validator-deployment.sh" "$operation" --handoff "$validator_handoff" --private-eks-session-handoff "$session_handoff"
    ;;
esac
