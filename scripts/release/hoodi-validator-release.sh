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
  hoodi-validator-release.sh infrastructure apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --work-dir /new-absolute-directory
  hoodi-validator-release.sh ops-inputs prepare --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --zero-work-dir /absolute/zero-work-dir --output-dir /new-absolute-directory
  hoodi-validator-release.sh stage plan|apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json
USAGE
  exit 64
}

command_name="${1:-}"; [ -n "$command_name" ] || usage
shift
operation=''; bundle_root=''; inputs=''; work_dir=''; session_handoff=''; output_dir=''
case "$command_name" in
  infrastructure|ops-inputs|stage)
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
    --private-eks-session-handoff) session_handoff="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

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
  .zero_resource_inputs == $zero and .validator_deployment_handoff == $validator and
  (.required_checkpoints | type == "array" and length == 6)
' "$inputs" >/dev/null || { printf '%s\n' 'inputs are not a bounded Hoodi zero-release contract' >&2; exit 65; }
[ -f "$zero_inputs" ] && [ ! -L "$zero_inputs" ] && [ -f "$validator_handoff" ] && [ ! -L "$validator_handoff" ] || { printf '%s\n' 'release contract references missing or unsafe inputs' >&2; exit 65; }
account="$(jq -er '.aws_account_id' "$inputs")"
jq -e --arg account "$account" '.schema_version == 1 and .aws_account_id == $account' "$zero_inputs" >/dev/null || { printf '%s\n' 'zero-resource input account does not match the release contract' >&2; exit 65; }
jq -e --arg account "$account" '.schema_version == 1 and .network == "hoodi" and .aws_account_id == $account and .staged_client_replicas == 0 and .staged_fence_replicas == 0' "$validator_handoff" >/dev/null || { printf '%s\n' 'validator handoff does not match the release contract or is not fenced' >&2; exit 65; }

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
  stage)
    [ "$operation" = plan ] || [ "$operation" = apply ] || usage
    [ -n "$session_handoff" ] && [ -z "$work_dir$output_dir" ] || usage
    "$release_dir/stage-hoodi-validator-deployment.sh" "$operation" --handoff "$validator_handoff" --private-eks-session-handoff "$session_handoff"
    ;;
esac
