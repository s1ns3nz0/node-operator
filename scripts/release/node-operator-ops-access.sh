#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: node-operator-ops-access.sh plan|apply|destroy --root BUNDLE_ROOT --config TFVARS --backend-config BACKEND_HCL --plan-file PRIVATE_SAVED_PLAN [--expected-sha SHA256] [--allow-create]'
}

operation="${1:-}"
[ "$operation" = plan ] || [ "$operation" = apply ] || [ "$operation" = destroy ] || { usage; exit 64; }
shift
root=""; config=""; backend_config=""; plan_file=""; expected_sha=""; allow_create=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    --backend-config) backend_config="${2:-}"; shift 2 ;;
    --plan-file) plan_file="${2:-}"; shift 2 ;;
    --expected-sha) expected_sha="${2:-}"; shift 2 ;;
    --allow-create) allow_create=true; shift ;;
    *) usage; exit 64 ;;
  esac
done
[ -d "$root/infra/ops-access" ] || { printf 'ops-access root is missing\n' >&2; exit 1; }
[ -f "$config" ] || { printf 'non-secret tfvars file is required\n' >&2; exit 1; }
[ -f "$backend_config" ] || { printf 'an isolated non-secret backend config is required\n' >&2; exit 1; }
[ -n "$plan_file" ] || { printf 'a private saved plan path is required\n' >&2; exit 64; }
command -v terraform >/dev/null 2>&1 || { printf 'terraform is required\n' >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { printf 'jq is required\n' >&2; exit 127; }
command -v shasum >/dev/null 2>&1 || { printf 'shasum is required\n' >&2; exit 127; }

module="$root/infra/ops-access"
guard="$root/scripts/ci/check-ops-access-ssm-retention-plan.sh"
[ -x "$guard" ] || { printf 'retained-host plan guard is missing\n' >&2; exit 1; }
plan_json="${plan_file}.json"

fresh_plan() {
  jq -e '
    ([.resource_changes[]? | select(.mode == "managed") | .change.actions[]] | index("create")) and
    ([.. | objects | .resources?[]? | select(.address == "aws_instance.host" and .mode == "managed") | .values.ebs_optimized] | all(. == true)) and
    ([.. | objects | .resources?[]? | select(.address == "data.aws_instance.retained_host[0]")] | length == 0)
  ' "$plan_json" >/dev/null
}

classify_plan() {
  terraform -chdir="$module" show -json "$plan_file" > "$plan_json"
  if bash "$guard" "$plan_json" >/dev/null; then
    [ "$allow_create" = false ] || { printf 'retained-host plan must not use --allow-create\n' >&2; exit 1; }
    printf 'retention\n'
  else
    [ "$allow_create" = true ] || { printf 'fresh creation requires --allow-create\n' >&2; exit 1; }
    fresh_plan || { printf 'plan is neither the reviewed retained host nor a secure fresh create\n' >&2; exit 1; }
    printf 'fresh\n'
  fi
}

terraform -chdir="$module" init -input=false -backend-config="$backend_config"
case "$operation" in
  plan)
    [ ! -e "$plan_file" ] || { printf 'refusing to overwrite saved plan\n' >&2; exit 1; }
    terraform -chdir="$module" plan -input=false -var-file="$config" -out="$plan_file"
    mode="$(classify_plan)"
    plan_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"
    printf 'saved_plan_mode=%s saved_plan_sha256=%s\n' "$mode" "$plan_sha"
    ;;
  apply)
    [ -n "$expected_sha" ] || { printf 'apply requires --expected-sha for the reviewed saved plan\n' >&2; exit 64; }
    [ -f "$plan_file" ] || { printf 'saved plan is missing\n' >&2; exit 1; }
    actual_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"
    [ "$actual_sha" = "$expected_sha" ] || { printf 'saved plan hash mismatch\n' >&2; exit 1; }
    mode="$(classify_plan)"
    actual_sha="$(shasum -a 256 "$plan_file" | awk '{print $1}')"
    [ "$actual_sha" = "$expected_sha" ] || { printf 'saved plan changed during validation\n' >&2; exit 1; }
    terraform -chdir="$module" apply -input=false "$plan_file"
    ;;
  destroy)
    printf 'destroy requires a separately reviewed explicit destroy-plan interface; direct destroy is disabled\n' >&2
    exit 1
    ;;
esac
