#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 MODULE_DIRECTORY OUTPUT_DIRECTORY [MODULE_RELATIVE_TFVARS]" >&2
  exit 64
fi
module_directory="$1"
output_directory="$2"
tfvars_path="${3:-fixtures/offline-baseline.tfvars}"
workspace="$output_directory/terraform-source"

if [[ "$tfvars_path" == /* || "$tfvars_path" == *\\* || "$tfvars_path" =~ (^|/)\.{1,2}(/|$) ]]; then
  echo "MODULE_RELATIVE_TFVARS must be a safe module-relative path" >&2
  exit 64
fi

mkdir -p "$workspace"
cp -a "$module_directory/." "$workspace"
rm -f "$workspace/backend.tf"
test -f "$workspace/$tfvars_path" || { echo "tfvars file does not exist in module: $tfvars_path" >&2; exit 66; }

export TF_DATA_DIR="$output_directory/terraform-data"
# Synthetic credentials prevent the provider from probing runner metadata.
# This script never contacts AWS: the caller runs it with network disabled.
export AWS_ACCESS_KEY_ID=offline
export AWS_SECRET_ACCESS_KEY=offline
export AWS_EC2_METADATA_DISABLED=true
terraform -chdir="$workspace" fmt -check -recursive
terraform -chdir="$workspace" init -backend=false -input=false -get=false -lockfile=readonly
terraform -chdir="$workspace" validate
terraform -chdir="$workspace" plan -refresh=false -input=false -var-file="$tfvars_path" -out="$output_directory/plan"
terraform -chdir="$workspace" show -json "$output_directory/plan" > "$output_directory/plan.json"
"$(cd "$(dirname "$0")" && pwd)/check-plan-boundary.sh" "$output_directory/plan.json"
