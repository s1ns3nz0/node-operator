#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="$root/infra/ops-access"
guard="$root/scripts/ci/check-ops-access-ssm-retention-plan.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ops-access-retention.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

"$root/scripts/ci/validate-terraform-module-offline.sh" "$module" "$scratch/offline" >/dev/null
grep -F 'variable "retained_host_instance_id"' "$module/variables.tf" >/dev/null
grep -F 'var.retained_host_instance_id == null || var.retained_host_instance_id == "i-02c57d75e7f6810b1"' "$module/variables.tf" >/dev/null
grep -F 'ebs_optimized                        = local.retain_existing_host ? false : true' "$module/main.tf" >/dev/null
grep -F 'ebs_optimized_support == "default"' "$module/main.tf" >/dev/null
grep -E '^  monitoring[[:space:]]*=[[:space:]]*false$' "$module/main.tf" >/dev/null
grep -F 'encrypted   = true' "$module/main.tf" >/dev/null
grep -F 'volume_type = "gp3"' "$module/main.tf" >/dev/null
grep -F 'http_tokens                 = "required"' "$module/main.tf" >/dev/null
if grep -Eq 'ignore_changes|checkov:skip' "$module/main.tf" "$module/variables.tf"; then
  printf 'retained-host implementation must not suppress drift or Checkov findings\n' >&2
  exit 1
fi

jq -n '
  # Synthetic plan identities only; no live state or saved-plan content is embedded.
  def resources: [
    {address:"aws_iam_instance_profile.host",mode:"managed",type:"aws_iam_instance_profile",values:{id:"profile-id"}},
    {address:"aws_iam_role.host",mode:"managed",type:"aws_iam_role",values:{id:"role-id"}},
    {address:"aws_iam_role_policy_attachment.ssm",mode:"managed",type:"aws_iam_role_policy_attachment",values:{id:"attachment-id"}},
    {address:"aws_instance.host",mode:"managed",type:"aws_instance",values:{id:"i-02c57d75e7f6810b1",instance_type:"t3.micro",ebs_optimized:false}},
    {address:"aws_security_group.host",mode:"managed",type:"aws_security_group",values:{id:"sg-host"}},
    {address:"aws_vpc_security_group_egress_rule.to_cluster",mode:"managed",type:"aws_vpc_security_group_egress_rule",values:{id:"egress-cluster"}},
    {address:"aws_vpc_security_group_egress_rule.to_endpoints",mode:"managed",type:"aws_vpc_security_group_egress_rule",values:{id:"egress-endpoints"}},
    {address:"aws_vpc_security_group_ingress_rule.cluster",mode:"managed",type:"aws_vpc_security_group_ingress_rule",values:{id:"ingress-cluster"}},
    {address:"aws_vpc_security_group_ingress_rule.endpoints",mode:"managed",type:"aws_vpc_security_group_ingress_rule",values:{id:"ingress-endpoints"}}
  ];
  {prior_state:{values:{root_module:{resources:resources}}},planned_values:{root_module:{resources:(resources | map(if .address == "aws_vpc_security_group_ingress_rule.cluster" then .address = "aws_vpc_security_group_ingress_rule.cluster[0]" elif .address == "aws_vpc_security_group_ingress_rule.endpoints" then .address = "aws_vpc_security_group_ingress_rule.endpoints[0]" else . end))}},resource_changes:[
    {address:"aws_instance.host",mode:"managed",type:"aws_instance",change:{actions:["no-op"],before:{id:"i-02c57d75e7f6810b1",instance_type:"t3.micro",ebs_optimized:false},after:{id:"i-02c57d75e7f6810b1",instance_type:"t3.micro",ebs_optimized:false},after_unknown:{ebs_optimized:false}}}
  ]}
' > "$scratch/valid.json"
bash "$guard" "$scratch/valid.json" >/dev/null

for mutation in \
  'del(.prior_state.values.root_module.resources)' \
  '.resource_changes[0].change.actions=["create"]' \
  '.resource_changes[0].change.actions=["delete"]' \
  '.resource_changes[0].change.actions=["delete","create"]' \
  '.prior_state.values.root_module.resources[3].values.id="i-00000000000000000"' \
  '.prior_state.values.root_module.resources[3].values.instance_type="t3.small"' \
  '.resource_changes[0].change.after_unknown.ebs_optimized=true' \
  '.planned_values.root_module.resources += [{address:"aws_instance.other",mode:"managed",type:"aws_instance",values:{id:"i-00000000000000000",instance_type:"t3.micro",ebs_optimized:false}}]' \
  '.resource_changes += [{address:"aws_instance.other",mode:"managed",type:"aws_instance",change:{actions:["update"],before:{id:"i-00000000000000000",instance_type:"t3.micro",ebs_optimized:true},after:{id:"i-00000000000000000",instance_type:"t3.micro",ebs_optimized:false},after_unknown:{ebs_optimized:false}}}]'; do
  jq "$mutation" "$scratch/valid.json" > "$scratch/invalid.json"
  if bash "$guard" "$scratch/invalid.json" >/dev/null 2>&1; then
    printf 'unsafe retained-host plan accepted\n' >&2
    exit 1
  fi
done

classify_checkov() {
  local report="$1" exit_code="$2"
  if [ "$exit_code" -gt 1 ]; then printf 'ERROR\n'; return; fi
  if ! jq -e '.check_type == "terraform" and (.summary | type == "object")' "$report" >/dev/null 2>&1; then printf 'ERROR\n'; return; fi
  if jq -e '.summary.parsing_errors > 0' "$report" >/dev/null; then printf 'ERROR\n'; return; fi
  if jq -e '.summary.resource_count == 0' "$report" >/dev/null; then printf 'UNKNOWN\n'; return; fi
  if jq -e '.summary.failed > 0' "$report" >/dev/null; then printf 'FAIL\n'; return; fi
  if jq -e '.summary.passed > 0' "$report" >/dev/null; then printf 'PASS\n'; return; fi
  if jq -e '.summary.skipped > 0' "$report" >/dev/null; then printf 'SKIPPED\n'; return; fi
  printf 'UNKNOWN\n'
}

for case_name in default opt-in; do
  report="$scratch/checkov-$case_name.json"
  set +e
  checkov -d "$module" --framework terraform --var-file "$module/fixtures/ssm-retention-$case_name.tfvars" --output json --quiet --skip-download --compact > "$report"
  checkov_exit=$?
  set -e
  status="$(classify_checkov "$report" "$checkov_exit")"
  case "$case_name" in
    default)
      test "$status" = "FAIL" || { printf 'Checkov default status is %s, not expected FAIL\n' "$status" >&2; exit 1; }
      jq -e 'any(.results.failed_checks[]?; .check_id == "CKV_AWS_135")' "$report" >/dev/null
      jq -e 'any(.results.failed_checks[]?; .check_id == "CKV_AWS_126")' "$report" >/dev/null
      ;;
    opt-in)
      test "$status" = "FAIL" || { printf 'Checkov opt-in status is %s, not expected FAIL\n' "$status" >&2; exit 1; }
      jq -e 'any(.results.failed_checks[]?; .check_id == "CKV_AWS_126")' "$report" >/dev/null
      ;;
  esac
done

for status_case in FAIL UNKNOWN SKIPPED ERROR; do
  case "$status_case" in
    FAIL) jq -n '{check_type:"terraform",summary:{resource_count:1,passed:0,failed:1,skipped:0,parsing_errors:0}}' > "$scratch/status.json"; exit_code=0 ;;
    UNKNOWN) jq -n '{check_type:"terraform",summary:{resource_count:0,passed:0,failed:0,skipped:0,parsing_errors:0}}' > "$scratch/status.json"; exit_code=0 ;;
    SKIPPED) jq -n '{check_type:"terraform",summary:{resource_count:1,passed:0,failed:0,skipped:1,parsing_errors:0}}' > "$scratch/status.json"; exit_code=0 ;;
    ERROR) jq -n '{check_type:"terraform",summary:{resource_count:1,passed:1,failed:0,skipped:0,parsing_errors:0}}' > "$scratch/status.json"; exit_code=2 ;;
  esac
  test "$(classify_checkov "$scratch/status.json" "$exit_code")" = "$status_case"
done

printf 'PASS ops-access retained-host opt-in, saved-plan guard, and Checkov status handling.\n'
