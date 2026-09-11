#!/usr/bin/env bash
set -euo pipefail
umask 077

# This wrapper owns command flags, the default workspace, and per-module state
# paths. Inherited Terraform options must not force migration, skip refresh,
# redirect state, or enable raw sensitive logging. Only this process is changed.
for terraform_environment_name in ${!TF_CLI_ARGS@}; do
  unset "$terraform_environment_name"
done
unset TF_DATA_DIR TF_WORKSPACE TF_INPUT TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER

usage() {
  cat <<'USAGE'
usage:
  node-operator-release.sh verify --bundle-root DIRECTORY
  node-operator-release.sh bootstrap plan|apply --bundle-root DIRECTORY --config FILE
  node-operator-release.sh zero apply --bundle-root DIRECTORY \
    (--inputs FILE | --bootstrap-config FILE --foundation-config FILE --baseline-config FILE) \
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
bootstrap_config=""; foundation_config=""; baseline_config=""; inputs=""; work_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root) bundle_root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    --bootstrap-config) bootstrap_config="${2:-}"; shift 2 ;;
    --foundation-config) foundation_config="${2:-}"; shift 2 ;;
    --baseline-config) baseline_config="${2:-}"; shift 2 ;;
    --inputs) inputs="${2:-}"; shift 2 ;;
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
  if [[ "$input" == *.json ]]; then
    jq -e -s 'length == 1 and (.[0] | type == "object")' "$input" >/dev/null || fail "baseline JSON must contain one object"
    jq -e '
      [.enable_temporary_ssm_ops_host,
       .enable_argocd_bootstrap_cluster_admin,
       .enable_vault_bootstrap_cluster_admin] |
      all(. == null or . == false)
    ' "$input" >/dev/null || fail "SSM and temporary cluster-admin require their separately approved phases"
    return
  fi
  if rg -n '^[[:space:]]*enable_temporary_ssm_ops_host[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$input" >/dev/null; then
    fail "SSM operations access belongs to the isolated ops-access command"
  fi
  if rg -n '^[[:space:]]*enable_(argocd|vault)_bootstrap_cluster_admin[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$input" >/dev/null; then
    fail "temporary cluster-admin bootstrap requires its separately approved phase"
  fi
}

reject_derived_network_inputs() {
  local input="$1"
  if [[ "$input" == *.json ]]; then
    jq -e 'type == "object" and (has("network_source") or has("foundation_network") or has("hoodi_nat_gateway_id") | not)' "$input" >/dev/null || fail "zero apply derives foundation network inputs; remove network overrides from baseline JSON"
  elif rg -n '^[[:space:]]*(network_source|foundation_network|hoodi_nat_gateway_id)[[:space:]]*=' "$input" >/dev/null; then
    fail "zero apply derives foundation network inputs; remove network_source, foundation_network, and hoodi_nat_gateway_id from --baseline-config"
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

write_runtime_s3_backend() {
  # The bootstrap root deliberately has no checked-in backend block: its first
  # apply must use local state while it creates the S3 backend.  Add this only
  # at the hand-off boundary, never to the archived module.
  local module="$1"
  local destination="$module/node-operator-runtime-backend.tf"
  [ ! -L "$destination" ] || fail "bootstrap runtime backend configuration must not be a symlink"
  cat > "$destination" <<'HCL'
terraform {
  backend "s3" {}
}
HCL
  chmod 600 "$destination"
}

verify_s3_backend_identity() {
  # Terraform records the configured backend independently of a checkpoint.
  # Check every destination selector before treating a work directory as
  # resumable; a state file named "bootstrap-output.json" proves nothing.
  local module="$1" backend_json="$2" state_key="$3"
  local metadata="$module/.terraform/terraform.tfstate"
  [ -f "$metadata" ] && [ ! -L "$metadata" ] || fail "bootstrap is not configured for the expected remote backend"
  jq -e --arg key "$state_key" --slurpfile expected "$backend_json" '
    $expected[0] as $expected |
    .backend.type == "s3" and
    .backend.config.bucket == $expected.bucket and
    .backend.config.key == $key and
    .backend.config.region == $expected.region and
    .backend.config.dynamodb_table == $expected.dynamodb_table and
    .backend.config.kms_key_id == $expected.kms_key_id and
    .backend.config.encrypt == true
  ' "$metadata" >/dev/null 2>&1 || fail "bootstrap backend identity does not match the generated S3 destination"
}

capture_state() {
  local module="$1" destination="$2" allow_empty="${3:-false}"
  [ ! -L "$destination" ] || fail "state backup must not be a symlink"
  [ ! -e "$destination" ] || [ -f "$destination" ] || fail "state backup must be a regular file"
  local temporary
  temporary="$(mktemp "${destination}.pending.XXXXXX")" || fail "cannot allocate private state backup"
  chmod 600 "$temporary"
  if ! terraform -chdir="$module" state pull > "$temporary"; then
    unlink "$temporary"
    fail "could not read Terraform state for bootstrap migration"
  fi
  if [ ! -s "$temporary" ] && [ "$allow_empty" = true ]; then
    # Terraform state pull returns successful empty output when the configured
    # backend has no object.  Record a canonical empty state privately so the
    # foreign-state guard can distinguish it from a pull failure.
    printf '%s\n' '{"version":4,"resources":[],"outputs":{}}' > "$temporary"
  fi
  jq -se 'length == 1 and (.[0] | type == "object" and .version == 4 and (.resources | type == "array") and (.outputs | type == "object"))' "$temporary" >/dev/null 2>&1 || {
    unlink "$temporary"; fail "Terraform returned an invalid bootstrap state";
  }
  mv -f "$temporary" "$destination"
  chmod 600 "$destination"
}

assert_empty_remote_state() {
  local state_file="$1"
  jq -se 'length == 1 and (.[0] | type == "object" and .version == 4 and (.resources | type == "array" and length == 0) and (.outputs | type == "object" and length == 0))' "$state_file" >/dev/null 2>&1 || fail "target S3 backend already contains state; refusing to overwrite a foreign remote state"
}

assert_migration_state_transition() {
  local before="$1" after="$2" receipt="$3" allow_reset="${4:-false}" temporary
  [ ! -L "$receipt" ] || fail "migration receipt must not be a symlink"
  temporary="$(mktemp "${receipt}.pending.XXXXXX")" || fail "cannot allocate private migration receipt"
  chmod 600 "$temporary"
  # Terraform 1.5.7 has a documented empty-remote path that resets only
  # lineage and serial.  Every other state field must remain exact.  This is
  # deliberately narrow: it is not permission to ignore arbitrary metadata.
  if ! jq -S -e -s --argjson allow_reset "$allow_reset" '
    def valid_state:
      type == "object" and .version == 4 and
      (.serial | type == "number" and . >= 0 and floor == .) and
      (.lineage | type == "string" and test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")) and
      (.resources | type == "array") and (.outputs | type == "object");
    .[0] as $before | .[1] as $after |
    if length != 2 or ($before | valid_state | not) or ($after | valid_state | not) then error("invalid state")
    elif $before == $after then
      {mode:"identical",version:$after.version,serial_before:$before.serial,serial_after:$after.serial,lineage_before:$before.lineage,lineage_after:$after.lineage}
    elif ($allow_reset and ($before | del(.lineage, .serial)) == ($after | del(.lineage, .serial)) and
          $before.lineage != $after.lineage and $after.serial == 1) then
      {mode:"terraform-1.5-empty-remote-metadata-reset",version:$after.version,serial_before:$before.serial,serial_after:$after.serial,lineage_before:$before.lineage,lineage_after:$after.lineage}
    else error("unexpected state transition") end
  ' "$before" "$after" > "$temporary" 2>/dev/null; then
    unlink "$temporary"
    fail "bootstrap state/resources differ after remote migration; no downstream phase was started"
  fi
  mv -f "$temporary" "$receipt"
  chmod 600 "$receipt"
}

assert_no_change_plan() {
  local module="$1" config="$2" result=0
  terraform -chdir="$module" plan -input=false -detailed-exitcode -var-file="$config" >/dev/null || result=$?
  case "$result" in
    0) ;;
    2) fail "bootstrap migration has a non-empty reconciliation plan; no downstream phase was started" ;;
    *) fail "bootstrap migration reconciliation plan failed; no downstream phase was started" ;;
  esac
}

capture_pre_migration_local_state() {
  local module="$1" destination="$2"
  local runtime_backend="$module/node-operator-runtime-backend.tf"
  local disabled_backend="$module/.node-operator-runtime-backend.tf.local-only"
  # A hard process termination can occur between the private rename and its
  # restoration below.  Recover only the exact file this script generated;
  # unknown recovery artifacts remain a fail-closed operator investigation.
  if [ ! -e "$runtime_backend" ] && [ -e "$disabled_backend" ]; then
    [ -f "$disabled_backend" ] && [ ! -L "$disabled_backend" ] || fail "bootstrap local backend recovery artifact is not a regular file"
    cmp -s "$disabled_backend" <(printf 'terraform {\n  backend "s3" {}\n}\n') || fail "bootstrap local backend recovery artifact is not the generated migration boundary"
    mv "$disabled_backend" "$runtime_backend"
  fi
  if [ ! -e "$runtime_backend" ]; then
    [ ! -e "$disabled_backend" ] && [ ! -L "$disabled_backend" ] || fail "bootstrap local backend recovery path already exists"
    capture_state "$module" "$destination"
    return
  fi
  [ -f "$runtime_backend" ] && [ ! -L "$runtime_backend" ] || fail "bootstrap runtime backend configuration is not a regular file"
  cmp -s "$runtime_backend" <(printf 'terraform {\n  backend "s3" {}\n}\n') || fail "bootstrap runtime backend configuration is not the generated migration boundary"
  [ ! -e "$disabled_backend" ] && [ ! -L "$disabled_backend" ] || fail "bootstrap local backend recovery path already exists"
  # An interrupted interactive init leaves the generated S3 declaration in
  # place while Terraform remains configured locally.  Hide only our exact
  # generated declaration long enough to read and verify the local recovery
  # state, then restore it before probing or retrying migration.
  if ! (
    # Invoked indirectly by the scoped restoration traps below.
    # shellcheck disable=SC2329
    restore_runtime_backend() {
      if [ -f "$disabled_backend" ] && [ ! -e "$runtime_backend" ]; then
        mv "$disabled_backend" "$runtime_backend"
      fi
    }
    trap restore_runtime_backend EXIT INT TERM
    mv "$runtime_backend" "$disabled_backend"
    capture_state "$module" "$destination"
  ); then
    fail "could not recover local bootstrap state after interrupted migration"
  fi
}

migrate_bootstrap_state() {
  local module="$1" config="$2" backend_json="$3" state_key="$4" work="$5"
  local local_backup="$work/bootstrap.local-state.pre-migration.json"
  local remote_probe="$work/bootstrap-remote-probe"
  local remote_probe_backend="$remote_probe/node-operator-runtime-backend.tf"
  local remote_before="$work/bootstrap.remote-state.pre-migration.json"
  local remote_after="$work/bootstrap.remote-state.post-migration.json"

  [ -d "$module" ] && [ ! -L "$module" ] || fail "bootstrap module directory is unavailable for state migration"

  if [ -f "$module/.terraform/terraform.tfstate" ] && jq -e '.backend.type == "s3"' "$module/.terraform/terraform.tfstate" >/dev/null 2>&1; then
    [ -f "$local_backup" ] && [ ! -L "$local_backup" ] || fail "bootstrap checkpoint is not migration proof; the private pre-migration state backup is required to resume"
    [ -f "$remote_before" ] && [ ! -L "$remote_before" ] || fail "bootstrap migration requires its original empty-target observation"
    assert_empty_remote_state "$remote_before"
    verify_s3_backend_identity "$module" "$backend_json" "$state_key"
    capture_state "$module" "$remote_after"
    assert_migration_state_transition "$local_backup" "$remote_after" "$work/bootstrap.migration-state-transition.json" true
    assert_no_change_plan "$module" "$config"
    return
  fi

  # Preserve the local state before adding the backend declaration.  If an
  # interrupted run already left the backup, confirm that local state still
  # matches it instead of silently replacing the only recovery copy.
  if [ -f "$local_backup" ]; then
    local current_local="$work/bootstrap.local-state.resume-check.json"
    capture_pre_migration_local_state "$module" "$current_local"
    assert_migration_state_transition "$local_backup" "$current_local" "$work/bootstrap.local-state.resume-transition.json"
  else
    capture_pre_migration_local_state "$module" "$local_backup"
  fi

  # Probe the exact S3 identity from an independent, empty Terraform root.
  # This prevents init -migrate-state from being the first operation to touch
  # an existing remote object.
  [ ! -L "$remote_probe" ] || fail "bootstrap remote probe directory must not be a symlink"
  mkdir -p "$remote_probe"; chmod 700 "$remote_probe"
  [ ! -L "$remote_probe_backend" ] || fail "bootstrap remote probe backend configuration must not be a symlink"
  cat > "$remote_probe_backend" <<'HCL'
terraform {
  backend "s3" {}
}
HCL
  chmod 600 "$remote_probe_backend"
  terraform -chdir="$remote_probe" init -input=false -backend-config="$work/bootstrap.backend.hcl"
  verify_s3_backend_identity "$remote_probe" "$backend_json" "$state_key"
  capture_state "$remote_probe" "$remote_before" true
  assert_empty_remote_state "$remote_before"

  write_runtime_s3_backend "$module"
  # Intentionally interactive: Terraform presents its migration confirmation.
  # Do not add -force-copy, -reconfigure, -input=false, or a piped affirmative.
  terraform -chdir="$module" init -migrate-state -input=true -backend-config="$work/bootstrap.backend.hcl"
  verify_s3_backend_identity "$module" "$backend_json" "$state_key"
  capture_state "$module" "$remote_after"
  assert_migration_state_transition "$local_backup" "$remote_after" "$work/bootstrap.migration-state-transition.json" true
  assert_no_change_plan "$module" "$config"
}

copy_module() {
  local relative="$1" destination="$2"
  [ -d "$bundle_root/source/$relative" ] || fail "release bundle is missing $relative"
  [ ! -L "$destination" ] || fail "release module destination must not be a symlink"
  if [ -e "$destination" ]; then
    [ -d "$destination" ] || fail "release module destination must be a directory"
  else
    mkdir -p "$destination"; chmod 700 "$destination"
  fi
  # A checkpoint can be resumed with a newer verified bundle. Copy the module
  # contents, rather than the directory itself, so referenced non-Terraform
  # policy assets land at the module root and Terraform's local data remains.
  cp -R "$bundle_root/source/$relative/." "$destination"
}

apply_phase() {
  local module="$1" phase_config="$2" backend_config="$3" plan_file="$4"
  terraform -chdir="$module" init -input=false -backend-config="$backend_config"
  terraform -chdir="$module" plan -input=false -var-file="$phase_config" -out="$plan_file"
  terraform -chdir="$module" apply -input=false "$plan_file"
}

capture_terraform_output() {
  # Publish a checkpoint only after Terraform and JSON validation succeed.
  # A failed output query must not turn a partial apply into a completed phase.
  local module="$1" destination="$2" output_name="${3:-}" temporary
  [ ! -L "$destination" ] || fail "output checkpoint must not be a symlink"
  [ ! -e "$destination" ] || [ -f "$destination" ] || fail "output checkpoint must be a regular file"
  temporary="$(mktemp "${destination}.pending.XXXXXX")" || fail "cannot allocate private output checkpoint"
  chmod 600 "$temporary"
  if [ -n "$output_name" ]; then
    if ! terraform -chdir="$module" output -json "$output_name" > "$temporary"; then
      unlink "$temporary"
      fail "Terraform output query failed; checkpoint was not replaced"
    fi
  else
    if ! terraform -chdir="$module" output -json > "$temporary"; then
      unlink "$temporary"
      fail "Terraform output query failed; checkpoint was not replaced"
    fi
  fi
  if ! jq -se 'length == 1 and (.[0] | type == "object" and length > 0)' "$temporary" >/dev/null 2>&1; then
    unlink "$temporary"
    fail "Terraform output is not a nonempty JSON object; checkpoint was not replaced"
  fi
  mv -f "$temporary" "$destination"
}

verify_completed_phase() {
  # Read-only reconciliation: a saved output file is not proof of live state.
  # Exit 2 from plan means changes, not success; never apply them on this path.
  local module="$1" config="$2" checkpoint="$3" output_name="$4" result=0 temporary
  [ -d "$module" ] && [ ! -L "$module" ] || fail "saved phase lacks its original Terraform directory; restore that directory before resuming"
  [ -f "$checkpoint" ] && [ ! -L "$checkpoint" ] || fail "saved phase output is not a regular file"
  jq -se 'length == 1 and (.[0] | type == "object" and length > 0)' "$checkpoint" >/dev/null 2>&1 || fail "saved phase output is invalid; preserve state and reconcile before resuming"
  terraform -chdir="$module" plan -input=false -detailed-exitcode -var-file="$config" >/dev/null || result=$?
  case "$result" in
    0) ;;
    2) fail "saved phase differs from actual infrastructure or configuration; no changes applied; reconcile before resuming" ;;
    *) fail "saved phase could not be checked; verify authentication, backend and state before resuming" ;;
  esac
  temporary="$(mktemp "${checkpoint}.verify.XXXXXX")" || fail "cannot allocate private reconciliation file"
  if ! terraform -chdir="$module" output -json "$output_name" > "$temporary"; then
    unlink "$temporary"
    fail "saved phase output could not be read from Terraform state"
  fi
  if ! jq -es --slurpfile saved "$checkpoint" 'length == 1 and ($saved | length) == 1 and .[0] == $saved[0]' "$temporary" >/dev/null 2>&1; then
    unlink "$temporary"
    fail "saved phase output differs from Terraform state; no checkpoint replaced"
  fi
  unlink "$temporary"
}

zero_apply() {
  if [ -n "$inputs" ]; then
    [ -z "$bootstrap_config$foundation_config$baseline_config" ] || fail "--inputs cannot be combined with individual phase configs"
    case "$inputs" in /*) ;; *) fail "--inputs must be an absolute path" ;; esac
    [ -f "$inputs" ] && [ ! -L "$inputs" ] || fail "--inputs must name a regular file"
    local input_parent expected_bootstrap expected_foundation expected_baseline
    input_parent="$(cd "$(dirname "$inputs")" && pwd -P)"
    expected_bootstrap="$input_parent/bootstrap-state.tfvars.json"
    expected_foundation="$input_parent/foundation-network.tfvars.json"
    expected_baseline="$input_parent/baseline.tfvars.json"
    jq -e --arg bootstrap "$expected_bootstrap" --arg foundation "$expected_foundation" --arg baseline "$expected_baseline" '
      .schema_version == 1 and (.aws_account_id | test("^[0-9]{12}$")) and
      (.aws_region | test("^ap-northeast-(1|2)$")) and
      .bootstrap_config == $bootstrap and .foundation_config == $foundation and .baseline_config == $baseline
    ' "$inputs" >/dev/null || fail "--inputs is not a bounded zero-resource input contract"
    bootstrap_config="$expected_bootstrap"; foundation_config="$expected_foundation"; baseline_config="$expected_baseline"
  fi
  [ -n "$bootstrap_config" ] && [ -n "$foundation_config" ] && [ -n "$baseline_config" ] || fail "zero apply requires --inputs or all three phase configs"
  case "$work_dir" in /*) ;; *) fail "--work-dir must be an absolute directory" ;; esac
  [ ! -L "$work_dir" ] || fail "--work-dir must not be a symlink"
  if [ -e "$work_dir" ]; then
    [ -d "$work_dir" ] || fail "--work-dir must be a directory"
  else
    mkdir -p "$work_dir"; chmod 700 "$work_dir"
  fi
  require_command terraform
  require_nonsecret_file "$bootstrap_config"; require_nonsecret_file "$foundation_config"; require_nonsecret_file "$baseline_config"
  reject_privileged_baseline_inputs "$baseline_config"
  reject_derived_network_inputs "$baseline_config"

  local bootstrap_module="$work_dir/bootstrap-state" foundation_module="$work_dir/foundation-network" baseline_module="$work_dir/baseline"
  local bootstrap_backend="$work_dir/bootstrap.backend.hcl" foundation_backend="$work_dir/foundation.backend.hcl" baseline_backend="$work_dir/baseline.backend.hcl"
  local bootstrap_output="$work_dir/bootstrap-output.json" foundation_output="$work_dir/foundation-output.json" foundation_input="$work_dir/foundation-network.auto.tfvars.json" baseline_output="$work_dir/baseline-output.json" gitops_handoff="$work_dir/gitops-publisher-handoff.json" ops_handoff="$work_dir/ops-access-handoff.json"

  if [ ! -f "$bootstrap_output" ]; then
    [ ! -e "$bootstrap_module" ] || fail "incomplete bootstrap checkpoint; use a new work directory"
    copy_module infra/bootstrap-state "$bootstrap_module"
    terraform -chdir="$bootstrap_module" init -input=false -backend=false
    terraform -chdir="$bootstrap_module" plan -input=false -var-file="$bootstrap_config" -out="$work_dir/bootstrap.tfplan"
    terraform -chdir="$bootstrap_module" apply -input=false "$work_dir/bootstrap.tfplan"
    capture_terraform_output "$bootstrap_module" "$bootstrap_output" backend
  fi
  write_backend_config "$bootstrap_output" "node-operator/bootstrap-state/terraform.tfstate" "$bootstrap_backend"
  # A bootstrap output checkpoint alone does not prove where Terraform state is
  # configured.  Always prove the configured backend and semantic state before
  # allowing foundation or baseline work to begin.
  migrate_bootstrap_state "$bootstrap_module" "$bootstrap_config" "$bootstrap_output" \
    "node-operator/bootstrap-state/terraform.tfstate" "$work_dir"
  verify_completed_phase "$bootstrap_module" "$bootstrap_config" "$bootstrap_output" backend

  write_backend_config "$bootstrap_output" "node-operator/foundation-network/terraform.tfstate" "$foundation_backend"
  if [ ! -f "$foundation_output" ]; then
    [ ! -e "$foundation_module" ] || fail "incomplete foundation checkpoint; use a new work directory"
    copy_module infra/foundation-network "$foundation_module"
    apply_phase "$foundation_module" "$foundation_config" "$foundation_backend" "$work_dir/foundation.tfplan"
    capture_terraform_output "$foundation_module" "$foundation_output" network
  else
    verify_completed_phase "$foundation_module" "$foundation_config" "$foundation_output" network
  fi
  jq -e 'type == "object" and (.vpc_id | test("^vpc-[0-9a-f]+$")) and (.vpc_cidr | type == "string") and (.system_subnet_ids | type == "array" and length >= 2) and (.hoodi_subnet_ids | type == "array" and length >= 1) and (.system_route_table_id | test("^rtb-[0-9a-f]+$")) and (.hoodi_route_table_id | test("^rtb-[0-9a-f]+$")) and (.hoodi_nat_gateway_id | test("^nat-[0-9a-f]+$"))' "$foundation_output" >/dev/null || fail "foundation output is not a usable zero-resource network contract"
  jq '{network_source:"foundation", foundation_network:{vpc_id:.vpc_id, vpc_cidr:.vpc_cidr, system_subnet_ids:.system_subnet_ids, hoodi_subnet_ids:.hoodi_subnet_ids, system_route_table_id:.system_route_table_id, hoodi_route_table_id:.hoodi_route_table_id, hoodi_nat_gateway_id:.hoodi_nat_gateway_id}}' "$foundation_output" > "$foundation_input"
  chmod 600 "$foundation_input"

  copy_module infra/terraform "$baseline_module"
  cp "$foundation_input" "$baseline_module/foundation-network.auto.tfvars.json"
  write_backend_config "$bootstrap_output" "node-operator/baseline/terraform.tfstate" "$baseline_backend"
  apply_phase "$baseline_module" "$baseline_config" "$baseline_backend" "$work_dir/baseline.tfplan"
  capture_terraform_output "$baseline_module" "$baseline_output"
  deployment_region="$(jq -er '.aws_region' "$foundation_config")" || fail "foundation configuration lacks aws_region"
  jq -e --arg region "$deployment_region" '
    (.deployment_account_id.value | test("^[0-9]{12}$")) and
    (.cluster_name.value | test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")) and
    (.gitops_client_ecr_repository_url.value | test("^[0-9]{12}\\.dkr\\.ecr\\." + $region + "\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*$")) and
    (.github_gitops_client_ecr_publisher_role_arn.value | test("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_-]+$"))
  ' "$baseline_output" >/dev/null || fail "baseline did not emit the required GitOps publisher handoff"
  jq '{schema_version:"v1",gitops_repository:"s1ns3nz0/node-operator-gitops",publisher_environment:"gitops-client-ecr-publish",aws_account_id:.deployment_account_id.value,chart_repository:.gitops_client_ecr_repository_url.value,publisher_role_arn:.github_gitops_client_ecr_publisher_role_arn.value}' "$baseline_output" > "$gitops_handoff"
  jq --arg region "$deployment_region" --slurpfile foundation "$foundation_output" --slurpfile bootstrap "$bootstrap_output" '
    {schema_version:"v1",aws_region:$region,aws_account_id:.deployment_account_id.value,
     cluster_name:.cluster_name.value,
     vpc_id:$foundation[0].vpc_id,subnet_id:$foundation[0].system_subnet_ids[0],
     backend:{bucket:$bootstrap[0].bucket,dynamodb_table:$bootstrap[0].dynamodb_table,kms_key_id:$bootstrap[0].kms_key_id,region:$bootstrap[0].region,
       key:"node-operator/ops-access/terraform.tfstate"}}
  ' "$baseline_output" > "$ops_handoff"
  chmod 600 "$gitops_handoff" "$ops_handoff"
  printf 'PASS zero-resource infrastructure bootstrap completed. Configure the GitOps publisher from %s and prepare isolated SSM access from %s before Argo, Vault, and validator phases.\n' "$gitops_handoff" "$ops_handoff"
}

case "$command_name" in
  verify)
    [ -z "$operation$config$bootstrap_config$foundation_config$baseline_config$inputs$work_dir" ] || fail "verify accepts only --bundle-root"
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
