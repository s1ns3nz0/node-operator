#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s PLAN_JSON\n' "$0" >&2
  exit 64
fi

plan="$1"
test -f "$plan" || { printf 'missing plan JSON: %s\n' "$plan" >&2; exit 1; }

jq -e '
  . as $plan |
  def managed_resources:
    [.. | objects | .resources?[]? | select(.mode == "managed")];
  def normalized_address:
    if . == "aws_vpc_security_group_ingress_rule.cluster" then "aws_vpc_security_group_ingress_rule.cluster[0]"
    elif . == "aws_vpc_security_group_ingress_rule.endpoints" then "aws_vpc_security_group_ingress_rule.endpoints[0]"
    else . end;
  def identity_map:
    reduce .[] as $resource ({}; .[$resource.address | normalized_address] = {type:$resource.type,id:$resource.values.id});
  [
    "aws_iam_instance_profile.host",
    "aws_iam_role.host",
    "aws_iam_role_policy_attachment.ssm",
    "aws_instance.host",
    "aws_security_group.host",
    "aws_vpc_security_group_egress_rule.to_cluster",
    "aws_vpc_security_group_egress_rule.to_endpoints",
    "aws_vpc_security_group_ingress_rule.cluster[0]",
    "aws_vpc_security_group_ingress_rule.endpoints[0]"
  ] | sort as $expected_addresses |
  "aws_instance.host" as $host_address |
  "i-02c57d75e7f6810b1" as $host_id |
  ($plan.prior_state.values.root_module | managed_resources) as $before |
  ($plan.planned_values.root_module | managed_resources) as $after |
  [$plan.resource_changes[]? | select(.mode == "managed")] as $changes |
  [$before[] | select(.address == $host_address and .type == "aws_instance")] as $before_host |
  [$after[] | select(.address == $host_address and .type == "aws_instance")] as $after_host |
  [$changes[] | select(.address == $host_address and .type == "aws_instance")] as $host_change |
  ($before | map(.address | normalized_address) | sort) == $expected_addresses and
  ($after | map(.address) | sort) == $expected_addresses and
  (all($before[]; (.values.id | type == "string" and length > 0))) and
  (all($after[]; (.values.id | type == "string" and length > 0))) and
  (($before | identity_map) == ($after | identity_map)) and
  ($before_host | length) == 1 and
  ($after_host | length) == 1 and
  ($host_change | length) == 1 and
  ($before_host[0].values.id == $host_id) and
  ($before_host[0].values.instance_type == "t3.micro") and
  ($before_host[0].values.ebs_optimized == false) and
  ($after_host[0].values.id == $host_id) and
  ($after_host[0].values.instance_type == "t3.micro") and
  ($after_host[0].values.ebs_optimized == false) and
  ($host_change[0].change.actions == ["no-op"]) and
  ($host_change[0].change.before.id == $host_id) and
  ($host_change[0].change.after.id == $host_id) and
  ($host_change[0].change.before.instance_type == "t3.micro") and
  ($host_change[0].change.after.instance_type == "t3.micro") and
  ($host_change[0].change.before.ebs_optimized == false) and
  ($host_change[0].change.after.ebs_optimized == false) and
  (all($changes[]; (.change.actions | index("create") | not) and (.change.actions | index("delete") | not))) and
  (all($changes[]; .change.after_unknown.ebs_optimized != true)) and
  (all($before[]; if .values.ebs_optimized? == false then
    .address == $host_address and .type == "aws_instance" and .values.id == $host_id and .values.instance_type == "t3.micro"
  else true end)) and
  (all($after[]; if .values.ebs_optimized? == false then
    .address == $host_address and .type == "aws_instance" and .values.instance_type == "t3.micro"
  else true end)) and
  (all($changes[]; if .change.after.ebs_optimized? == false then
    .address == $host_address and .type == "aws_instance" and .change.before.id == $host_id and .change.after.instance_type == "t3.micro"
  else true end))
' "$plan" >/dev/null

printf 'PASS ops-access retained-host plan is identity-bound and non-destructive.\n'
