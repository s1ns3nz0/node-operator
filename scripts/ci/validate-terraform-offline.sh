#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 2 ] || { echo "usage: $0 MODULE_DIRECTORY OUTPUT_DIRECTORY" >&2; exit 64; }
module_directory="$1"
output_directory="$2"
workspace="$output_directory/terraform-source"

mkdir -p "$workspace"
cp -a "$module_directory/." "$workspace"
rm -f "$workspace/backend.tf"

export TF_DATA_DIR="$output_directory/terraform-data"
# Synthetic credentials prevent the provider from probing runner metadata.
# This script never contacts AWS: the caller runs it with network disabled.
export AWS_ACCESS_KEY_ID=offline
export AWS_SECRET_ACCESS_KEY=offline
export AWS_EC2_METADATA_DISABLED=true
terraform -chdir="$workspace" fmt -check -recursive
terraform -chdir="$workspace" init -backend=false -input=false -get=false -lockfile=readonly
terraform -chdir="$workspace" validate
terraform -chdir="$workspace" plan -refresh=false -input=false -var-file=fixtures/offline-baseline.tfvars -out="$output_directory/plan"
terraform -chdir="$workspace" show -json "$output_directory/plan" > "$output_directory/plan.json"
"$(cd "$(dirname "$0")" && pwd)/check-plan-boundary.sh" "$output_directory/plan.json"
