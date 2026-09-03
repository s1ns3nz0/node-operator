#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
fail() { printf 'FAIL Argo CD bootstrap enabled plan: %s\n' "$*" >&2; exit 1; }

"$script_dir/validate-terraform-offline.sh" \
  "$root/infra/terraform" \
  "$temporary_directory" \
  fixtures/offline-argocd-bootstrap.tfvars

plan="$temporary_directory/plan.json"
jq -e '
  any(.resource_changes[]?; .address == "aws_codebuild_project.argocd_bootstrap[0]" and (.change.actions | index("create")))
  and any(.resource_changes[]?; .address == "aws_eks_access_entry.argocd_bootstrap[0]" and (.change.actions | index("create")))
' "$plan" >/dev/null || fail 'enabled plan does not create the bootstrap project and its EKS access entry'

jq -e '
  ([.resource_changes[]? | select(.change.actions | index("create")) | .type]
    | any(. == "aws_nat_gateway" or . == "aws_internet_gateway") | not)
  and
  ([.resource_changes[]? | select(.change.actions | index("create")) | select(.change.after.public_access == true)] | length == 0)
' "$plan" >/dev/null || fail 'enabled plan crosses the private infrastructure boundary'

printf 'PASS Argo CD bootstrap enabled offline plan is private-boundary compliant.\n'
