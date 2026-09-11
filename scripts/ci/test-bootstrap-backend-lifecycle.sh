#!/usr/bin/env bash
# Check objective: Verify initial local state and consented backend transition with real Terraform, without AWS.
# Side effects: Applies only a disposable local output, with no providers or cloud resources.
set -euo pipefail
umask 077
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
unset TF_CLI_ARGS TF_CLI_ARGS_init TF_CLI_ARGS_plan TF_CLI_ARGS_apply TF_DATA_DIR TF_WORKSPACE TF_INPUT
export CHECKPOINT_DISABLE=1
mkdir "$scratch/local" "$scratch/s3"
printf '%s\n' 'output "fixture" { value = "non-secret-local-only" }' > "$scratch/local/main.tf"
terraform -chdir="$scratch/local" init -input=false -backend=false >/dev/null
terraform -chdir="$scratch/local" apply -input=false -auto-approve >/dev/null
test -s "$scratch/local/terraform.tfstate"
cp "$scratch/local/terraform.tfstate" "$scratch/before.tfstate"

# Declaring S3 before the initial local apply is not repaired by backend=false.
printf '%s\n' 'terraform {' '  backend "s3" {}' '}' > "$scratch/s3/backend.tf"
terraform -chdir="$scratch/s3" init -input=false -backend=false >/dev/null
if terraform -chdir="$scratch/s3" plan -input=false > "$scratch/rejected.log" 2>&1; then
  printf 'FAIL: uninitialized S3 backend unexpectedly allowed a plan\n' >&2
  exit 1
fi
grep -Fq 'Backend initialization required' "$scratch/rejected.log"

# Substitute a local destination to test actual migration without a remote call.
printf '%s\n' 'terraform {' '  backend "local" { path = "migrated.tfstate" }' '}' > "$scratch/local/backend.tf"
if terraform -chdir="$scratch/local" init -input=false -migrate-state > "$scratch/consent.log" 2>&1; then
  printf 'FAIL: state migration unexpectedly proceeded without consent\n' >&2
  exit 1
fi
test ! -e "$scratch/local/migrated.tfstate"
# The supplied consent is exclusively for this non-secret, local-only fixture.
terraform -chdir="$scratch/local" init -input=true -migrate-state > "$scratch/migration.log" 2>&1 <<'CONSENT'
yes
CONSENT
cmp "$scratch/before.tfstate" "$scratch/local/migrated.tfstate"
terraform -chdir="$scratch/local" plan -input=false -detailed-exitcode >/dev/null
printf 'PASS local bootstrap, uninitialized S3 rejection, and consented local state migration preserve exact state.\n'
