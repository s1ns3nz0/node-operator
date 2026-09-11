#!/usr/bin/env bash
# Check objective: Verify zero-resource ownership boundaries and guarded bootstrap state migration.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entrypoint="$root/scripts/release/node-operator-release.sh"
baseline="$root/infra/terraform"
foundation="$root/infra/foundation-network"

for file in \
  "$root/release/zero-resource-bootstrap-state.tfvars.example" \
  "$root/release/zero-resource-foundation-network.tfvars.example" \
  "$root/release/zero-resource-baseline.tfvars.example"; do
  [ -f "$file" ] || { printf 'missing zero-resource example: %s\n' "$file" >&2; exit 1; }
done

rg -F 'network_source:"foundation"' "$entrypoint" >/dev/null
rg -F 'init -migrate-state -input=true -backend-config="$work/bootstrap.backend.hcl"' "$entrypoint" >/dev/null
rg -F 'migrate_bootstrap_state' "$entrypoint" >/dev/null
rg -F 'backend "s3" {}' "$entrypoint" >/dev/null
rg -F 'target S3 backend already contains state; refusing to overwrite a foreign remote state' "$entrypoint" >/dev/null
rg -F 'bootstrap state/resources differ after remote migration; no downstream phase was started' "$entrypoint" >/dev/null
rg -F 'A bootstrap output checkpoint alone does not prove where Terraform state is' "$entrypoint" >/dev/null
rg -F 'bootstrap migration has a non-empty reconciliation plan' "$entrypoint" >/dev/null
rg -F 'could not recover local bootstrap state after interrupted migration' "$entrypoint" >/dev/null
rg -F 'terraform-1.5-empty-remote-metadata-reset' "$entrypoint" >/dev/null
if rg -n -- 'terraform .*-(force-copy|reconfigure)|terraform .*yes[[:space:]]*\|' "$entrypoint"; then
  printf 'bootstrap migration must remain explicit and interactive\n' >&2
  exit 1
fi
rg -F 'node-operator/foundation-network/terraform.tfstate' "$entrypoint" >/dev/null
rg -F 'node-operator/baseline/terraform.tfstate' "$entrypoint" >/dev/null
rg -F 'foundation-network.auto.tfvars.json' "$entrypoint" >/dev/null
rg -F '(.vpc_id | test("^vpc-[0-9a-f]+$"))' "$entrypoint" >/dev/null
rg -F 'vpc_id:.vpc_id' "$entrypoint" >/dev/null
if rg -F '.vpc_id.value' "$entrypoint" >/dev/null; then
  printf 'foundation output is already a direct Terraform output value and must not be dereferenced again\n' >&2
  exit 1
fi
if rg -F '$bootstrap[0].bucket.value' "$entrypoint" >/dev/null; then
  printf 'bootstrap output is already a direct Terraform output value and must not be dereferenced again\n' >&2
  exit 1
fi
rg -F 'gitops-publisher-handoff.json' "$entrypoint" >/dev/null
rg -F 'ops-access-handoff.json' "$entrypoint" >/dev/null
rg -F -- '--inputs cannot be combined with individual phase configs' "$entrypoint" >/dev/null
rg -F 'zero apply requires --inputs or all three phase configs' "$entrypoint" >/dev/null
rg -F 'recover_missing_phase_output "$bootstrap_module"' "$entrypoint" >/dev/null
rg -F 'recover_missing_phase_output "$foundation_module"' "$entrypoint" >/dev/null
rg -F 'cp -R "$bundle_root/source/$relative/." "$destination"' "$entrypoint" >/dev/null
rg -F 'bootstrap-state.tfvars.json' "$entrypoint" >/dev/null
rg -F 'github_gitops_client_ecr_publisher_role_arn' "$entrypoint" >/dev/null
rg -F 'backend "s3" {}' "$baseline/backend.tf" >/dev/null
rg -F 'vpc_cidr' "$foundation/outputs.tf" >/dev/null
rg -F 'variable "network_source"' "$baseline/variables.tf" >/dev/null
rg -F 'variable "foundation_network"' "$baseline/variables.tf" >/dev/null
rg -F 'prevent_destroy = true' "$baseline/network.tf" >/dev/null
rg -F 'local.system_subnet_ids' "$baseline/eks.tf" "$baseline/endpoints.tf" >/dev/null
rg -F 'local.hoodi_subnet_ids' "$baseline/eks.tf" >/dev/null
if rg -n 'node-operator-tfstate-106760547719-apne2|23528ef1-681c-41c3-a565-d19d3ec98c37' "$baseline/backend.tf"; then
  printf 'baseline backend remains bound to historical state\n' >&2
  exit 1
fi
printf 'PASS zero-resource release contract preserves state and network ownership boundaries.\n'
bash "$root/scripts/ci/test-bootstrap-state-migration.sh"
