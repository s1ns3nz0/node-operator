#!/usr/bin/env bash
# Check objective: Exercise migration, backend identity and retry failure boundaries without cloud access.
set -euo pipefail

# Exercises the release boundary with a Terraform-shaped mock.  The mock never
# exposes state on stdout: the release script must redirect each state pull to
# a private file before inspecting it.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entrypoint="$root/scripts/release/node-operator-release.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/node-operator-bootstrap-migration.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
bin="$scratch/bin"; mkdir -p "$bin"

cat > "$bin/terraform" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
directory=""; args=()
for arg in "$@"; do
  case "$arg" in -chdir=*) directory="${arg#-chdir=}" ;; *) args+=("$arg") ;; esac
done
for forbidden in TF_CLI_ARGS TF_CLI_ARGS_init TF_CLI_ARGS_plan TF_LOG TF_DATA_DIR TF_WORKSPACE; do
  [ -z "${!forbidden:-}" ] || { printf 'unsafe Terraform environment was inherited\n' >&2; exit 98; }
done
command="${args[0]}"; printf '%s %s\n' "$(basename "$directory")" "${args[*]}" >> "$TEST_TERRAFORM_LOG"
state='{"version":4,"serial":23,"lineage":"43433424-4274-677a-050f-5f725c172eac","resources":[{"module":"","mode":"managed","type":"aws_s3_bucket","name":"state","provider":"provider[\"registry.terraform.io/hashicorp/aws\"]","instances":[{"schema_version":0,"attributes":{"id":"state"}}]}],"outputs":{}}'
empty='{"version":4,"serial":0,"lineage":"43433424-4274-677a-050f-5f725c172eac","resources":[],"outputs":{}}'
wrong='{"version":4,"serial":23,"lineage":"43433424-4274-677a-050f-5f725c172eac","resources":[{"module":"","mode":"managed","type":"aws_s3_bucket","name":"different","provider":"provider[\"registry.terraform.io/hashicorp/aws\"]","instances":[]}],"outputs":{}}'
reset='{"version":4,"serial":1,"lineage":"1ab1c89b-c841-5119-dff7-48606a2148bf","resources":[{"module":"","mode":"managed","type":"aws_s3_bucket","name":"state","provider":"provider[\"registry.terraform.io/hashicorp/aws\"]","instances":[{"schema_version":0,"attributes":{"id":"state"}}]}],"outputs":{}}'
bad_reset='{"version":4,"serial":2,"lineage":"1ab1c89b-c841-5119-dff7-48606a2148bf","resources":[{"module":"","mode":"managed","type":"aws_s3_bucket","name":"state","provider":"provider[\"registry.terraform.io/hashicorp/aws\"]","instances":[{"schema_version":0,"attributes":{"id":"state"}}]}],"outputs":{}}'
metadata() {
  mkdir -p "$directory/.terraform"
  local state_key="node-operator/bootstrap-state/terraform.tfstate"
  if [[ "$directory" == *foundation-network ]]; then state_key="node-operator/foundation-network/terraform.tfstate"; fi
  if [[ "$directory" == */baseline ]]; then state_key="node-operator/baseline/terraform.tfstate"; fi
  if [ "${TF_CASE:-success}" = wrongbackend ]; then
    printf '%s' '{"backend":{"type":"s3","config":{"bucket":"wrong","key":"wrong","region":"ap-northeast-2","dynamodb_table":"lock","kms_key_id":"kms","encrypt":true}}}' > "$directory/.terraform/terraform.tfstate"
  else
    printf '%s' '{"backend":{"type":"s3","config":{"bucket":"bucket","key":"'"$state_key"'","region":"ap-northeast-2","dynamodb_table":"lock","kms_key_id":"kms","encrypt":true}}}' > "$directory/.terraform/terraform.tfstate"
  fi
}
case "$command" in
  init)
    if [[ " ${args[*]} " == *' -backend=false '* ]]; then
      mkdir -p "$directory/.terraform"; printf '%s' '{"backend":{"type":"local","config":{}}}' > "$directory/.terraform/terraform.tfstate"
    elif [[ " ${args[*]} " == *' -migrate-state '* ]]; then
      [ "${TF_CASE:-success}" != migrate_fail ] || exit 19
      metadata
    else
      metadata
    fi ;;
  plan)
    if [[ " ${args[*]} " != *' -detailed-exitcode '* ]]; then
      for arg in "${args[@]}"; do [[ "$arg" == -out=* ]] && : > "${arg#-out=}"; done
    fi ;;
  apply)
    if [[ "$directory" == *bootstrap-state ]]; then printf '%s' "$state" > "$directory/terraform.tfstate"; fi ;;
  output)
    if [ "${args[2]:-}" = backend ]; then
      [ "${TF_CASE:-success}" != bootstrap_output_fail ] || exit 21
      printf '%s\n' '{"bucket":"bucket","region":"ap-northeast-2","dynamodb_table":"lock","kms_key_id":"kms"}'
    elif [ "${args[2]:-}" = network ]; then
      [ "${TF_CASE:-success}" != foundation_output_fail ] || exit 22
      printf '%s\n' '{"vpc_id":"vpc-abc","vpc_cidr":"10.0.0.0/16","system_subnet_ids":["subnet-a","subnet-b"],"hoodi_subnet_ids":["subnet-c"],"system_route_table_id":"rtb-a","hoodi_route_table_id":"rtb-b","hoodi_nat_gateway_id":"nat-a"}'
    else
      [ "${TF_CASE:-success}" != baseline_output_fail ] || exit 23
      [ "${#args[@]}" = 2 ] || exit 24
      printf '%s\n' '{"deployment_account_id":{"value":"123456789012"},"cluster_name":{"value":"node-operator"},"gitops_client_ecr_repository_url":{"value":"123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator"},"github_gitops_client_ecr_publisher_role_arn":{"value":"arn:aws:iam::123456789012:role/publisher"}}'
    fi ;;
  state)
    if [[ "$directory" == *bootstrap-remote-probe ]]; then
      [ "${TF_CASE:-success}" = foreign ] && printf '%s\n' "$state" || printf '%s\n' "$empty"
    elif [ "${TF_CASE:-success}" = metadata_reset ] && [ -f "$directory/.terraform/terraform.tfstate" ] && rg -F '"s3"' "$directory/.terraform/terraform.tfstate" >/dev/null; then
      printf '%s\n' "$reset"
    elif [ "${TF_CASE:-success}" = invalid_reset ] && [ -f "$directory/.terraform/terraform.tfstate" ] && rg -F '"s3"' "$directory/.terraform/terraform.tfstate" >/dev/null; then
      printf '%s\n' "$bad_reset"
    elif [ "${TF_CASE:-success}" = mismatch ] && [ -f "$directory/.terraform/terraform.tfstate" ] && rg -F '"s3"' "$directory/.terraform/terraform.tfstate" >/dev/null; then
      printf '%s\n' "$wrong"
    else
      printf '%s\n' "$state"
    fi ;;
  *) exit 97 ;;
esac
MOCK
chmod +x "$bin/terraform"

bundle="$scratch/bundle"; mkdir -p "$bundle/source/release"
cp -R "$root/infra" "$bundle/source/infra"
cp "$root/release/hoodi-release-contract.json" "$bundle/source/release/"
jq -n --arg digest "$(shasum -a 256 "$bundle/source/release/hoodi-release-contract.json" | awk '{print $1}')" \
  '{entries:[{path:"source/release/hoodi-release-contract.json",sha256:$digest}]}' > "$bundle/bundle-manifest.json"
for name in bootstrap foundation baseline; do printf '%s\n' '{"aws_region":"ap-northeast-2"}' > "$scratch/$name.tfvars"; done

run_case() {
  local case_name="$1" expected="$2"
  local work="${3:-$scratch/work-$case_name}"
  local log="$scratch/$case_name.log"
  local output="$scratch/$case_name.out"
  set +e
  PATH="$bin:$PATH" TEST_TERRAFORM_LOG="$log" TF_CASE="$case_name" \
    TF_CLI_ARGS=-force-copy TF_CLI_ARGS_init='-force-copy -input=false' TF_CLI_ARGS_plan=-refresh=false TF_LOG=TRACE \
    TF_DATA_DIR=/unapproved-state-directory TF_WORKSPACE=unapproved-workspace \
    bash "$entrypoint" zero apply --bundle-root "$bundle" \
    --bootstrap-config "$scratch/bootstrap.tfvars" --foundation-config "$scratch/foundation.tfvars" --baseline-config "$scratch/baseline.tfvars" --work-dir "$work" >"$output" 2>&1
  result=$?
  set -e
  if { [ "$expected" = pass ] && [ "$result" -ne 0 ]; } || { [ "$expected" = fail ] && [ "$result" -eq 0 ]; }; then
    cat "$output" >&2
    exit 1
  fi
  printf '%s\n' "$work"
}

success_work="$(run_case success pass)"
success_log="$scratch/success.log"
local_init="$(rg -n 'bootstrap-state init -input=false -backend=false' "$success_log" | cut -d: -f1)"
probe_init="$(rg -n 'bootstrap-remote-probe init -input=false' "$success_log" | cut -d: -f1)"
migrate="$(rg -n 'bootstrap-state init -migrate-state ' "$success_log" | cut -d: -f1)"
reconcile="$(rg -n 'bootstrap-state plan -input=false -detailed-exitcode' "$success_log" | head -1 | cut -d: -f1)"
foundation="$(rg -n 'foundation-network init ' "$success_log" | head -1 | cut -d: -f1)"
[ "$local_init" -lt "$probe_init" ] && [ "$probe_init" -lt "$migrate" ] && [ "$migrate" -lt "$reconcile" ] && [ "$reconcile" -lt "$foundation" ] || { cat "$success_log" >&2; exit 1; }
rg -F 'init -migrate-state -input=true -backend-config=' "$success_log" >/dev/null
if rg -n -- 'migrate-state.*(-input=false|-force-copy|-reconfigure)' "$success_log"; then exit 1; fi
[ -f "$success_work/bootstrap.local-state.pre-migration.json" ] || exit 1

for failure in migrate_fail wrongbackend mismatch foreign; do
  run_case "$failure" fail >/dev/null
  if rg -F 'foundation-network init' "$scratch/$failure.log" >/dev/null; then
    printf 'downstream phase began after bootstrap migration failure: %s\n' "$failure" >&2
    exit 1
  fi
done
run_case metadata_reset pass >/dev/null
run_case invalid_reset fail >/dev/null
migrate_retry_work="$(run_case migrate_fail fail)"
run_case success pass "$migrate_retry_work" >/dev/null
mismatch_retry_work="$(run_case mismatch fail)"
run_case mismatch fail "$mismatch_retry_work" >/dev/null
for phase in bootstrap foundation baseline; do
  partial_work="$(run_case "${phase}_output_fail" fail)"
  if [ "$phase" = foundation ]; then
    metadata_file="$partial_work/foundation-network/.terraform/terraform.tfstate"
    cp "$metadata_file" "$partial_work/foundation-metadata.original.json"
    jq '.backend.config.key = "unapproved/terraform.tfstate"' "$partial_work/foundation-metadata.original.json" > "$metadata_file"
    run_case foundation_recovery_wrong_backend fail "$partial_work" >/dev/null
    if rg -q '^foundation-network (state|plan|apply|output) ' "$scratch/foundation_recovery_wrong_backend.log"; then
      printf 'foundation recovery used an unapproved backend\n' >&2; exit 1
    fi
    cp "$partial_work/foundation-metadata.original.json" "$metadata_file"
  fi
  run_case "${phase}_recovered" pass "$partial_work" >/dev/null
  # Completed resource application must not be repeated to recover its output.
  module="bootstrap-state"
  [ "$phase" != foundation ] || module="foundation-network"
  [ "$phase" != baseline ] || module="baseline"
  [ "$(rg -c "^$module apply " "$scratch/${phase}_output_fail.log")" = 1 ]
  if rg -q "^$module apply " "$scratch/${phase}_recovered.log"; then
    printf 'checkpoint recovery repeated resource application\n' >&2; exit 1
  fi
  [ -f "$partial_work/${phase}-output.json.recovery-state.json" ]
done
run_case completed_resume pass "$success_work" >/dev/null
if rg -q ' apply ' "$scratch/completed_resume.log"; then
  printf 'completed deployment was applied again during reconciliation\n' >&2; exit 1
fi
for boundary in network backend output; do
  case "$boundary" in
    network) boundary_file="$success_work/baseline/foundation-network.auto.tfvars.json" ;;
    backend) boundary_file="$success_work/baseline/.terraform/terraform.tfstate" ;;
    output) boundary_file="$success_work/baseline-output.json" ;;
  esac
  cp "$boundary_file" "$scratch/baseline-$boundary.original.json"
  printf '%s\n' '{"changed":true}' > "$boundary_file"
  run_case "baseline_changed_$boundary" fail "$success_work" >/dev/null
  if rg -q ' apply ' "$scratch/baseline_changed_$boundary.log"; then
    printf 'baseline drift triggered resource application\n' >&2; exit 1
  fi
  cp "$scratch/baseline-$boundary.original.json" "$boundary_file"
done
printf 'PASS bootstrap migration mocks enforce local backup, remote identity, state equivalence, and downstream ordering.\n'
