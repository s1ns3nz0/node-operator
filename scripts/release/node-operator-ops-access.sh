#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() { printf '%s\n' 'usage: node-operator-ops-access.sh plan|apply|destroy --root BUNDLE_ROOT --config TFVARS --backend-config BACKEND_HCL --plan-file PRIVATE_SAVED_PLAN [--expected-sha SHA256] [--allow-create]'; }
operation="${1:-}"
[ "$operation" = plan ] || [ "$operation" = apply ] || [ "$operation" = destroy ] || { usage; exit 64; }
shift
root=""; config=""; backend_config=""; plan_file=""; expected_sha=""; allow_create=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;; --config) config="${2:-}"; shift 2 ;;
    --backend-config) backend_config="${2:-}"; shift 2 ;; --plan-file) plan_file="${2:-}"; shift 2 ;;
    --expected-sha) expected_sha="${2:-}"; shift 2 ;; --allow-create) allow_create=true; shift ;;
    *) usage; exit 64 ;;
  esac
done

private_path() {
  local candidate="$1" parent mode
  case "$candidate" in /*) ;; *) printf 'plan path must be absolute\n' >&2; return 1 ;; esac
  [ ! -L "$candidate" ] || { printf 'plan path must not be a symlink\n' >&2; return 1; }
  parent="$(dirname "$candidate")"
  [ -d "$parent" ] || { printf 'plan directory is missing\n' >&2; return 1; }
  while [ "$parent" != / ]; do
    # macOS exposes /tmp and /var through the /private volume.  Those fixed
    # system aliases are resolved by the OS; every caller-controlled component
    # still has to be a real directory.
    case "$parent" in
      /private|/var|/tmp) ;;
      *) [ ! -L "$parent" ] || { printf 'plan directory must not traverse a symlink\n' >&2; return 1; } ;;
    esac
    parent="$(dirname "$parent")"
  done
  mode="$(stat -f '%OLp' "$(dirname "$candidate")" 2>/dev/null || stat -c '%a' "$(dirname "$candidate")")"
  [ $((8#$mode & 077)) -eq 0 ] || { printf 'plan directory must not be accessible by group or others\n' >&2; return 1; }
}

[ -d "$root/infra/ops-access" ] || { printf 'ops-access root is missing\n' >&2; exit 1; }
[ -f "$config" ] || { printf 'non-secret tfvars file is required\n' >&2; exit 1; }
[ -f "$backend_config" ] || { printf 'an isolated non-secret backend config is required\n' >&2; exit 1; }
[ -n "$plan_file" ] || { printf 'a private saved plan path is required\n' >&2; exit 64; }
private_path "$plan_file" || exit 1
command -v terraform >/dev/null 2>&1 || { printf 'terraform is required\n' >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 127; }
command -v shasum >/dev/null 2>&1 || { printf 'shasum is required\n' >&2; exit 127; }
module="$root/infra/ops-access"; guard="$root/scripts/ci/check-ops-access-ssm-retention-plan.sh"
[ -x "$guard" ] || { printf 'retained-host plan guard is missing\n' >&2; exit 1; }

fresh_plan() {
  jq -e '
    def managed: [.. | objects | .resources?[]? | select(.mode == "managed")];
    # Creation legitimately leaves provider-computed IDs/addresses unknown.  Do
    # not let that relax any host hardening field; an unknown SG/profile is
    # allowed only when this same plan creates the owned reference.
    def known_security_configuration:
      (.ebs_optimized != true) and (.monitoring != true) and
      (.associate_public_ip_address != true) and (.subnet_id != true) and
      (.metadata_options[0].http_tokens != true) and
      (.metadata_options[0].http_endpoint != true) and
      (.metadata_options[0].http_put_response_hop_limit != true) and
      (.root_block_device[0].encrypted != true) and (.root_block_device[0].volume_type != true);
    . as $plan |
    ($plan.planned_values.root_module | managed | map(select(.address == "aws_instance.host" and .type == "aws_instance"))) as $planned_hosts |
    ($plan.planned_values.root_module | managed | map(select(.type == "aws_instance"))) as $planned_instances |
    [$plan.resource_changes[]? | select(.mode == "managed" and .address == "aws_instance.host" and .type == "aws_instance")] as $host_changes |
    [$plan.resource_changes[]? | select(.mode == "managed" and .type == "aws_instance")] as $instance_changes |
    [$plan.resource_changes[]? | select(.mode == "managed" and .address == "aws_security_group.host" and .type == "aws_security_group" and (.change.actions | index("create")))] as $owned_sg_changes |
    [$plan.resource_changes[]? | select(.mode == "managed" and .address == "aws_iam_instance_profile.host" and .type == "aws_iam_instance_profile" and (.change.actions | index("create")))] as $owned_profile_changes |
    [ $plan.configuration.root_module.resources[]? | select(.address == "aws_instance.host" and .mode == "managed" and .type == "aws_instance") ] as $configured_hosts |
    ($plan.prior_state.values.root_module | managed | map(select(.address == "aws_instance.host"))) as $prior_hosts |
    ([.. | objects | .id? | select(. == "i-02c57d75e7f6810b1")] | length == 0) and
    ($plan.variables | has("retained_host_instance_id")) and
    ($plan.variables.retained_host_instance_id | has("value")) and
    ($plan.variables.retained_host_instance_id.value == null) and
    ($plan.prior_state.values.root_module | managed | length == 0) and
    ($prior_hosts | length == 0) and ($planned_hosts | length == 1) and ($planned_instances | length == 1) and
    ($host_changes | length == 1) and ($instance_changes | length == 1) and
    ($owned_sg_changes | length == 1) and
    ($host_changes[0].change.actions == ["create"]) and ($host_changes[0].change.after == $planned_hosts[0].values) and
    ($configured_hosts | length > 0) and
    (all($configured_hosts[]; .expressions.iam_instance_profile.references == ["aws_iam_instance_profile.host.name"] and .expressions.vpc_security_group_ids.references == ["aws_security_group.host.id"])) and
    ($host_changes[0].change.after_unknown | known_security_configuration) and
    ($planned_hosts[0].values.ebs_optimized == true) and ($planned_hosts[0].values.monitoring == false) and
    ($planned_hosts[0].values.associate_public_ip_address == false) and
    ($planned_hosts[0].values.subnet_id | type == "string" and length > 0) and
    (($host_changes[0].change.after_unknown.iam_instance_profile == true) or
      ($planned_hosts[0].values.iam_instance_profile == $owned_profile_changes[0].change.after.name)) and
    ($host_changes[0].change.after_unknown.vpc_security_group_ids == [true]) and
    ($planned_hosts[0].values.metadata_options | type == "array" and length == 1) and
    ($planned_hosts[0].values.metadata_options[0].http_tokens == "required") and
    ($planned_hosts[0].values.metadata_options[0].http_endpoint == "enabled") and
    ($planned_hosts[0].values.metadata_options[0].http_put_response_hop_limit == 1) and
    ($planned_hosts[0].values.root_block_device | type == "array" and length == 1) and
    ($planned_hosts[0].values.root_block_device[0].encrypted == true) and ($planned_hosts[0].values.root_block_device[0].volume_type == "gp3")
  ' "$1" >/dev/null
}

render_json() {
  local output="$1" existing="${2:-false}"
  if [ "$existing" = true ]; then
    [ -f "$output" ] && [ ! -L "$output" ] || { printf 'temporary plan JSON is unsafe\n' >&2; return 1; }
  else
    [ ! -e "$output" ] && [ ! -L "$output" ] || { printf 'refusing to overwrite plan JSON\n' >&2; return 1; }
  fi
  terraform -chdir="$module" show -json "$plan_file" > "$output"
  jq -e . "$output" >/dev/null
}
classify_plan() {
  local json="$1"
  if bash "$guard" "$json" >/dev/null; then
    [ "$allow_create" = false ] || { printf 'retained-host plan must not use --allow-create\n' >&2; return 1; }
    printf 'retention\n'
  else
    [ "$allow_create" = true ] || { printf 'fresh creation requires --allow-create\n' >&2; return 1; }
    fresh_plan "$json" || { printf 'plan is neither the reviewed retained host nor a secure fresh create\n' >&2; return 1; }
    printf 'fresh\n'
  fi
}

terraform -chdir="$module" init -input=false -backend-config="$backend_config"
case "$operation" in
  plan)
    [ ! -e "$plan_file" ] && [ ! -L "$plan_file" ] || { printf 'refusing to overwrite saved plan\n' >&2; exit 1; }
    plan_json="${plan_file}.json"; private_path "$plan_json" || exit 1
    [ ! -e "$plan_json" ] && [ ! -L "$plan_json" ] || { printf 'refusing to overwrite saved plan JSON\n' >&2; exit 1; }
    terraform -chdir="$module" plan -input=false -var-file="$config" -out="$plan_file"
    render_json "$plan_json"; mode="$(classify_plan "$plan_json")"
    plan_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"
    printf 'saved_plan_mode=%s saved_plan_sha256=%s\n' "$mode" "$plan_sha"
    ;;
  apply)
    [ -n "$expected_sha" ] || { printf 'apply requires --expected-sha for the reviewed saved plan\n' >&2; exit 64; }
    [ -f "$plan_file" ] && [ ! -L "$plan_file" ] || { printf 'saved plan is missing or unsafe\n' >&2; exit 1; }
    actual_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"; [ "$actual_sha" = "$expected_sha" ] || { printf 'saved plan hash mismatch\n' >&2; exit 1; }
    plan_json="$(mktemp "$(dirname "$plan_file")/.node-operator-ops-access-plan.XXXXXX")"; trap 'rm -f "$plan_json"' EXIT
    render_json "$plan_json" true; mode="$(classify_plan "$plan_json")"
    actual_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"; [ "$actual_sha" = "$expected_sha" ] || { printf 'saved plan changed during validation\n' >&2; exit 1; }
    terraform -chdir="$module" apply -input=false "$plan_file"
    ;;
  destroy)
    printf 'destroy requires a separately reviewed explicit destroy-plan interface; direct destroy is disabled\n' >&2
    exit 1 ;;
esac
