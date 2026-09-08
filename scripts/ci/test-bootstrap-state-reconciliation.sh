#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
module="$root/infra/bootstrap-state"
variables="$module/variables.tf"
main="$module/main.tf"
outputs="$module/outputs.tf"
versions="$module/versions.tf"
runbook="$root/docs/operations/bootstrap-state-reconciliation.md"
fail() { printf 'FAIL bootstrap-state reconciliation: %s\n' "$*" >&2; exit 1; }
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

for required in \
  'variable "state_bucket_name"' \
  'default     = null' \
  'variable "baseline_state_key"' \
  'default     = "node-operator/baseline/terraform.tfstate"' \
  'node-operator/[a-z0-9][a-z0-9-]{0,62}/terraform\\.tfstate' \
  'variable "backend_principal_arns"' \
  'Exact same-account IAM role ARNs'; do
  rg -F "$required" "$variables" >/dev/null || fail "missing validated reconciliation contract: $required"
done

for required in \
  'generated_state_bucket' \
  'coalesce(var.state_bucket_name, local.generated_state_bucket)'; do
  rg -F "$required" "$main" >/dev/null || fail "missing generated-name preservation contract: $required"
done

rg -F 'key            = var.baseline_state_key' "$outputs" >/dev/null || fail 'backend output does not expose the configured state key'
rg -F 'allowed_account_ids = [var.aws_account_id]' "$versions" >/dev/null || fail 'provider account guard is missing'
rg -F '^arn:aws:iam::[0-9]{12}:role/' "$variables" >/dev/null || fail 'backend role syntax validation is missing'
rg -F '^arn:aws:iam::${var.aws_account_id}:role/' "$main" >/dev/null || fail 'backend roles are not constrained to the configured account'
rg -F 'precondition {' "$main" >/dev/null || fail 'same-account backend role validation must be a resource precondition'

test "$(rg -F -c 'lifecycle { prevent_destroy = true }' "$main")" -ge 3 || fail 'state bucket, access-log bucket, and lock table must be destruction-protected'
rg -F 'AllowNamedBackendRolesS3DataCrypto' "$main" >/dev/null || fail 'S3 CMK data-plane allowlist is missing'
rg -F 'AllowNamedBackendRolesDescribeStateKey' "$main" >/dev/null || fail 'S3 CMK describe allowlist is missing'
rg -F 'Action    = ["kms:Decrypt", "kms:GenerateDataKey"]' "$main" >/dev/null || fail 'S3 CMK data-plane permissions are not the exact required actions'
! rg -F 'kms:GenerateDataKey*' "$main" >/dev/null || fail 'S3 CMK data-plane permissions must not include GenerateDataKeyWithoutPlaintext'
rg -F '"kms:ViaService"    = "s3.${var.aws_region}.amazonaws.com"' "$main" >/dev/null || fail 'S3 CMK service restriction is missing'
rg -F '"kms:EncryptionContext:aws:s3:arn" = "${aws_s3_bucket.state.arn}/*"' "$main" >/dev/null || fail 'S3 CMK encryption-context restriction is missing'
! rg -F 'kms:CreateGrant' "$main" >/dev/null || fail 'DynamoDB CMK grant semantics must remain deferred'

# Evaluate actual Terraform plans and variable validation in a disposable,
# backend-free copy. The test-only provider override has no AWS endpoint.
cp -R "$module/." "$workspace/module"
cp "$workspace/module/fixtures/offline-provider-override.tf" "$workspace/module/override.tf"
terraform -chdir="$workspace/module" init -backend=false -get=false -lockfile=readonly -input=false >/dev/null

terraform -chdir="$workspace/module" plan -refresh=false -input=false \
  -var='aws_account_id=106760547719' \
  -out="$workspace/default.plan" >/dev/null
terraform -chdir="$workspace/module" show -json "$workspace/default.plan" > "$workspace/default.json"
jq -e 'any(.resource_changes[]?; .address == "aws_s3_bucket.state" and .change.after.bucket == "node-operator-tfstate-106760547719-apnortheast2")' "$workspace/default.json" >/dev/null || fail 'default bucket plan changed or nullable default did not validate'

terraform -chdir="$workspace/module" plan -refresh=false -input=false \
  -var='aws_account_id=106760547719' \
  -var='state_bucket_name=node-operator-tfstate-106760547719-apne2' \
  -var='baseline_state_key=node-operator/t2/terraform.tfstate' \
  -out="$workspace/legacy.plan" >/dev/null
terraform -chdir="$workspace/module" show -json "$workspace/legacy.plan" > "$workspace/legacy.json"
jq -e 'any(.resource_changes[]?; .address == "aws_s3_bucket.state" and .change.after.bucket == "node-operator-tfstate-106760547719-apne2")' "$workspace/legacy.json" >/dev/null || fail 'legacy bucket override did not evaluate'

expect_invalid_plan() {
  local expected_message="$1"
  shift
  if terraform -chdir="$workspace/module" plan -refresh=false -input=false "$@" >"$workspace/invalid-plan.out" 2>&1; then
    fail "invalid input unexpectedly planned: $expected_message"
  fi
  rg -F "$expected_message" "$workspace/invalid-plan.out" >/dev/null || fail "invalid input did not report: $expected_message"
}

expect_invalid_plan 'state_bucket_name must be null or a 3-63 character lowercase S3 bucket name' \
  -var='aws_account_id=106760547719' \
  -var='state_bucket_name=INVALID_BUCKET'

expect_invalid_plan 'baseline_state_key must be node-operator/<environment>/terraform.tfstate' \
  -var='aws_account_id=106760547719' \
  -var='baseline_state_key=node-operator/T2/terraform.tfstate'

expect_invalid_plan 'backend_principal_arns must contain only exact IAM role ARNs' \
  -var='aws_account_id=106760547719' \
  -var='backend_principal_arns=["arn:aws:iam::106760547719:user/not-a-role"]'

expect_invalid_plan 'backend_principal_arns must contain only IAM roles in aws_account_id' \
  -var='aws_account_id=106760547719' \
  -var='backend_principal_arns=["arn:aws:iam::999999999999:role/not-this-account"]'

# The backticks are literal Markdown required by the operator runbook.
# shellcheck disable=SC2016
for required in \
  'node-operator-tfstate-106760547719-apne2' \
  'node-operator/t2/terraform.tfstate' \
  'It is not a fresh `terraform apply`' \
  'operator_root="$(mktemp -d' \
  'aws_s3_bucket_server_side_encryption_configuration.state' \
  'node-operator-terraform-lock' \
  'private backend configuration file'; do
  rg -F "$required" "$runbook" >/dev/null || fail "runbook omits required reconciliation guidance: $required"
done

! rg -F 'terraform -chdir=infra/bootstrap-state' "$runbook" >/dev/null || fail 'runbook must execute Terraform only from a private module copy'
! rg -F 'EXACT_STATE_CMK_ID' "$runbook" >/dev/null || fail 'runbook must not instruct importing an unobserved state CMK'
! rg -F 'aws_kms_key.state EXACT' "$runbook" >/dev/null || fail 'runbook must not include an unobserved state CMK import command'

printf 'PASS bootstrap-state reconciliation contract is bounded and import-only.\n'
