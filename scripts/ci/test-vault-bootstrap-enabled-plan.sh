#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
fail() { printf 'FAIL Vault bootstrap enabled plan: %s\n' "$*" >&2; exit 1; }

"$script_dir/validate-terraform-offline.sh" \
  "$root/infra/terraform" \
  "$temporary_directory" \
  fixtures/offline-vault-bootstrap.tfvars

plan="$temporary_directory/plan.json"
jq -e '
  any(.resource_changes[]?; .address == "aws_codebuild_project.vault_bootstrap[0]" and (.change.actions | index("create")))
  and any(.resource_changes[]?; .address == "aws_eks_access_policy_association.vault_bootstrap_cluster_admin[0]" and (.change.actions | index("create")))
  and any(.resource_changes[]?; .address == "aws_ecr_repository.private_gitops[\"vault\"]" and (.change.actions | index("create")))
' "$plan" >/dev/null || fail 'enabled plan omits the Vault delivery executor, temporary EKS access, or private ECR destination'

jq -e '
  ([.resource_changes[]? | select(.change.actions | index("create")) | .type]
    | any(. == "aws_nat_gateway" or . == "aws_internet_gateway") | not)
' "$plan" >/dev/null || fail 'enabled plan introduces public network infrastructure'

printf 'PASS Vault bootstrap enabled offline plan is private-boundary compliant.\n'
