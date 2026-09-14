#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A container-mounted worktree has host-only Git metadata. Only source paths
# are needed, so this check also works from an extracted release bundle.
root="$(cd "$script_dir/../.." && pwd -P)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
fail() { printf 'FAIL Argo CD bootstrap enabled plan: %s\n' "$*" >&2; exit 1; }

"$script_dir/validate-terraform-offline.sh" \
  "$root/infra/terraform" \
  "$temporary_directory" \
  fixtures/offline-argocd-bootstrap.tfvars

plan="$temporary_directory/plan.json"
if [ "$#" -eq 1 ]; then
  # Export a synthetic plan for the host Python verifier when the pinned
  # Terraform container has no Python. The runner must verify this artifact.
  cp "$plan" "$1"
elif [ "$#" -eq 0 ]; then
  python3 "$script_dir/test-deployment-tags.py" "$plan"
else
  fail 'expected at most one synthetic plan output path'
fi
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
