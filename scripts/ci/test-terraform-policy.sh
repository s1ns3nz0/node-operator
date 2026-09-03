#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
require_command opa

opa test --fail-on-empty --ignore fixtures "$root/policy"
opa eval --format=json --data "$root/policy/terraform" --input "$root/policy/tests/fixtures/terraform-baseline-secure.json" 'data.nodeoperator.terraform.deny' | jq -e '.result[0].expressions[0].value == []' >/dev/null
for fixture in "$root"/policy/tests/fixtures/terraform-baseline-{broad-iam,invalid-node-group,public-endpoint,unencrypted}.json; do
  opa eval --format=json --data "$root/policy/terraform" --input "$fixture" 'data.nodeoperator.terraform.deny' | jq -e '.result[0].expressions[0].value | length > 0' >/dev/null
done
