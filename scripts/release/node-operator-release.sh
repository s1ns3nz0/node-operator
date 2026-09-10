#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
usage:
  node-operator-release.sh verify --bundle-root DIRECTORY
  node-operator-release.sh bootstrap plan|apply --bundle-root DIRECTORY --config FILE
  node-operator-release.sh zero apply --bundle-root DIRECTORY \
    --bootstrap-config FILE --foundation-config FILE --baseline-config FILE \
    --work-dir EMPTY_ABSOLUTE_DIRECTORY

`verify` validates every archived source/rendered file against bundle-manifest.json.
`bootstrap` preserves the existing non-secret baseline Terraform interface.
`zero apply` is the fresh-account infrastructure path: it creates and migrates
bootstrap state, applies foundation-network, and applies the baseline using the
foundation output. It does not create SSM operations access, initialize or
restore Vault, publish GitOps artifacts, read a Secret, or activate a validator.
USAGE
}

fail() { printf 'release bootstrap: %s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"; }

command_name="${1:-}"
[ -n "$command_name" ] || { usage; exit 64; }
shift

bundle_root=""; config=""; operation=""
bootstrap_config=""; foundation_config=""; baseline_config=""; work_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root) bundle_root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    --bootstrap-config) bootstrap_config="${2:-}"; shift 2 ;;
    --foundation-config) foundation_config="${2:-}"; shift 2 ;;
    --baseline-config) baseline_config="${2:-}"; shift 2 ;;
    --work-dir) work_dir="${2:-}"; shift 2 ;;
    plan|apply) operation="$1"; shift ;;
    *) usage; fail "unsupported argument: $1" ;;
  esac
done

[ -n "$bundle_root" ] || fail "--bundle-root is required"
[ -d "$bundle_root/source" ] || fail "bundle root must contain source/"
[ -f "$bundle_root/bundle-manifest.json" ] || fail "bundle root must contain bundle-manifest.json"
require_command jq
require_command shasum
require_command rg

verify_bundle() {
  local bad=0 path expected actual
  while IFS=$'\t' read -r path expected; do
    [ -f "$bundle_root/$path" ] || { printf 'missing archived path: %s\n' "$path" >&2; bad=1; continue; }
    actual="$(shasum -a 256 "$bundle_root/$path" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || { printf 'digest mismatch: %s\n' "$path" >&2; bad=1; }
  done < <(jq -r '.entries[] | [.path, .sha256] | @tsv' "$bundle_root/bundle-manifest.json")
  [ "$bad" -eq 0 ] || fail "bundle verification failed"
  jq -e '.schema_version == "v1" and .network == "hoodi" and .client_chart == {name:"node-operator-client",version_pattern:"^0\\.1\\.[0-9]+$",immutable_digest_required:true} and (.bootstrap.forbidden_inputs | length > 0)' \
    "$bundle_root/source/release/hoodi-release-contract.json" >/dev/null || fail "release contract is invalid"
  printf 'PASS release bundle and Hoodi contract verified.\n'
}

reject_privileged_baseline_inputs() {
  local input="$1"
  if rg -n '^[[:space:]]*enable_temporary_ssm_ops_host[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$input" >/dev/null; then
    fail "SSM operations access belongs to the isolated ops-access command"
  fi
  if rg -n '^[[:space:]]*enable_(argocd|vault)_bootstrap_cluster_admin[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$input" >/dev/null; then
    fail "temporary cluster-admin bootstrap requires its separately approved phase"
  fi
}

require_nonsecret_file() {
  local input="$1"
  [ -f "$input" ] && [ ! -L "$input" ] || fail "configuration must name a regular non-secret file"
  if rg -n -i '(vault[_-]?token|recovery[_-]?key|mnemonic|keystore|private[_-]?key|secret[_-]?access[_-]?key|aws_secret_access_key)[[:space:]]*=' "$input" >/dev/null; then
    fail "configuration contains a prohibited credential field"
  fi
}

write_backend_config() {
  local backend_json="$1" state_key="$2" destination="$3"
  jq -er --arg key "$state_key" '
    .bucket as $bucket | .region as $region | .dynamodb_table as $table | .kms_key_id as $kms |
    [$bucket, $region, $table, $kms] | all(type == "string" and length > 0) and
    ($key | test("^node-operator/[a-z0-9][a-z0-9-]{0,62}/terraform\\.tfstate$"))
  ' "$backend_json" >/dev/null || fail "bootstrap output is not a complete backend contract"
  jq -r --arg key "$state_key" '
    "bucket = \"\(.bucket)\"\n" + "key = \"\($key)\"\n" +
    "region = \"\(.region)\"\n" + "dynamodb_table = \"\(.dynamodb_table)\"\n" +
    "encrypt = true\n" + "kms_key_id = \"\(.kms_key_id)\"\n"
  ' "$backend_json" > "$destination"
  chmod 600 "$destination"
}

copy_module() {
  local relative="$1" destination="$2"
  [ -d "$bundle_root/source/$relative" ] || fail "release bundle is missing $relative"
  cp -R "$bundle_root/source/$relative" "$destination"
}

apply_phase() {
  local module="$1" phase_config="$2" backend_config="$3" plan_file="$4"
  terraform -chdir="$module" init -input=false -backend-config="$backend_config"
  terraform -chdir="$module" plan -input=false -var-file="$phase_config" -out="$plan_file"
  terraform -chdir="$module" apply -input=false "$plan_file"
}

zero_apply() {
  [ -n "$bootstrap_config" ] && [ -n "$foundation_config" ] && [ -n "$baseline_config" ] || fail "zero apply requires all three phase configs"
  case "$work_dir" in /*) ;; *) fail "--work-dir must be an absolute empty directory" ;; esac
  [ ! -e "$work_dir" ] || fail "--work-dir must not already exist"
  require_command terraform
  require_nonsecret_file "$bootstrap_config"; require_nonsecret_file "$foundation_config"; require_nonsecret_file "$baseline_config"
  reject_privileged_baseline_inputs "$baseline_config"
  if rg -n '^[[:space:]]*(network_source|foundation_network|hoodi_nat_gateway_id)[[:space:]]*=' "$baseline_config" >/dev/null; then
    fail "zero apply derives foundation network inputs; remove network_source, foundation_network, and hoodi_nat_gateway_id from --baseline-config"
  fi

  mkdir -p "$work_dir"; chmod 700 "$work_dir"
  local bootstrap_module="$work_dir/bootstrap-state" foundation_module="$work_dir/foundation-network" baseline_module="$work_dir/baseline"
  local bootstrap_backend="$work_dir/bootstrap.backend.hcl" foundation_backend="$work_dir/foundation.backend.hcl" baseline_backend="$work_dir/baseline.backend.hcl"
  local bootstrap_output="$work_dir/bootstrap-output.json" foundation_output="$work_dir/foundation-output.json" foundation_input="$work_dir/foundation-network.auto.tfvars.json" baseline_output="$work_dir/baseline-output.json" gitops_handoff="$work_dir/gitops-publisher-handoff.json"

  copy_module infra/bootstrap-state "$bootstrap_module"
  terraform -chdir="$bootstrap_module" init -input=false -backend=false
  terraform -chdir="$bootstrap_module" plan -input=false -var-file="$bootstrap_config" -out="$work_dir/bootstrap.tfplan"
  terraform -chdir="$bootstrap_module" apply -input=false "$work_dir/bootstrap.tfplan"
  terraform -chdir="$bootstrap_module" output -json backend > "$bootstrap_output"
  write_backend_config "$bootstrap_output" "node-operator/bootstrap-state/terraform.tfstate" "$bootstrap_backend"
  # Bootstrap begins in local state because the remote backend is being made.
  # Migration is explicit and never uses force-copy.
  terraform -chdir="$bootstrap_module" init -input=false -migrate-state -backend-config="$bootstrap_backend"

  copy_module infra/foundation-network "$foundation_module"
  write_backend_config "$bootstrap_output" "node-operator/foundation-network/terraform.tfstate" "$foundation_backend"
  apply_phase "$foundation_module" "$foundation_config" "$foundation_backend" "$work_dir/foundation.tfplan"
  terraform -chdir="$foundation_module" output -json network > "$foundation_output"
  jq -e 'type == "object" and (.vpc_id.value | test("^vpc-[0-9a-f]+$")) and (.vpc_cidr.value | type == "string") and (.system_subnet_ids.value | type == "array" and length >= 2) and (.hoodi_subnet_ids.value | type == "array" and length >= 1) and (.system_route_table_id.value | test("^rtb-[0-9a-f]+$")) and (.hoodi_route_table_id.value | test("^rtb-[0-9a-f]+$")) and (.hoodi_nat_gateway_id.value | test("^nat-[0-9a-f]+$"))' "$foundation_output" >/dev/null || fail "foundation output is not a usable zero-resource network contract"
  jq '{network_source:"foundation", foundation_network:{vpc_id:.vpc_id.value, vpc_cidr:.vpc_cidr.value, system_subnet_ids:.system_subnet_ids.value, hoodi_subnet_ids:.hoodi_subnet_ids.value, system_route_table_id:.system_route_table_id.value, hoodi_route_table_id:.hoodi_route_table_id.value, hoodi_nat_gateway_id:.hoodi_nat_gateway_id.value}}' "$foundation_output" > "$foundation_input"
  chmod 600 "$foundation_input"

  copy_module infra/terraform "$baseline_module"
  cp "$foundation_input" "$baseline_module/foundation-network.auto.tfvars.json"
  write_backend_config "$bootstrap_output" "node-operator/baseline/terraform.tfstate" "$baseline_backend"
  apply_phase "$baseline_module" "$baseline_config" "$baseline_backend" "$work_dir/baseline.tfplan"
  terraform -chdir="$baseline_module" output -json > "$baseline_output"
  jq -e '
    (.deployment_account_id.value | test("^[0-9]{12}$")) and
    (.gitops_client_ecr_repository_url.value | test("^[0-9]{12}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*$")) and
    (.github_gitops_client_ecr_publisher_role_arn.value | test("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_-]+$"))
  ' "$baseline_output" >/dev/null || fail "baseline did not emit the required GitOps publisher handoff"
  jq '{schema_version:"v1",gitops_repository:"s1ns3nz0/node-operator-gitops",publisher_environment:"gitops-client-ecr-publish",aws_account_id:.deployment_account_id.value,chart_repository:.gitops_client_ecr_repository_url.value,publisher_role_arn:.github_gitops_client_ecr_publisher_role_arn.value}' "$baseline_output" > "$gitops_handoff"
  chmod 600 "$gitops_handoff"
  printf 'PASS zero-resource infrastructure bootstrap completed. Configure the GitOps publisher from %s, then run separately approved Argo, SSM, Vault, and validator phases next.\n' "$gitops_handoff"
}

case "$command_name" in
  verify)
    [ -z "$operation$config$bootstrap_config$foundation_config$baseline_config$work_dir" ] || fail "verify accepts only --bundle-root"
    verify_bundle ;;
  bootstrap)
    [ "$operation" = plan ] || [ "$operation" = apply ] || fail "bootstrap requires plan or apply"
    [ -n "$config" ] && [ -f "$config" ] || fail "--config must name a readable non-secret tfvars file"
    verify_bundle; reject_privileged_baseline_inputs "$config"; require_command terraform
    terraform -chdir="$bundle_root/source/infra/terraform" init -input=false
    terraform -chdir="$bundle_root/source/infra/terraform" "$operation" -input=false -var-file="$config" ;;
  zero)
    [ "$operation" = apply ] || fail "zero requires apply"
    verify_bundle; zero_apply ;;
  *) usage; fail "unsupported command: $command_name" ;;
esac
