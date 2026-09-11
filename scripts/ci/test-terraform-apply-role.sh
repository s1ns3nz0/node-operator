#!/usr/bin/env bash
# Check objective: Prove custom same-account KMS lifecycle roles work without changing the historical default or accepting foreign roles.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
role="arn:aws:iam::123456789012:role/installer/custom-apply"
[ "$#" -le 1 ] || exit 64
assert_role() {
  jq -e --arg role "$2" '
    [.planned_values.root_module.resources[] | select(.type == "aws_iam_policy_document") |
     .values.statement[]? | select(.sid == "AllowTerraformApplyKeyLifecycleManagement")] |
    length >= 2 and all(.[]; .principals == [{type:"AWS",identifiers:[$role]}])
  ' "$1" >/dev/null
}
if [ "$#" = 1 ]; then
  assert_role "$1" "arn:aws:iam::123456789012:role/NodeOperatorTerraformApply"
fi
if ! TF_VAR_terraform_apply_role_arn="$role" bash "$root/scripts/ci/validate-terraform-offline.sh" "$root/infra/terraform" "$scratch" > "$scratch/validation.log" 2>&1; then
  tail -40 "$scratch/validation.log" >&2; exit 1
fi
assert_role "$scratch/plan.json" "$role"
if TF_DATA_DIR="$scratch/terraform-data" AWS_ACCESS_KEY_ID=offline AWS_SECRET_ACCESS_KEY=offline AWS_EC2_METADATA_DISABLED=true \
  terraform -chdir="$scratch/terraform-source" plan -refresh=false -input=false \
  -var-file=fixtures/offline-baseline.tfvars \
  -var='terraform_apply_role_arn=arn:aws:iam::999999999999:role/foreign' > "$scratch/foreign.log" 2>&1; then
  printf 'foreign KMS lifecycle principal was accepted\n' >&2; exit 1
fi
grep -F 'Terraform KMS lifecycle role must belong to the deployment account.' "$scratch/foreign.log" >/dev/null
printf 'PASS custom same-account KMS lifecycle role and foreign-role rejection.\n'
