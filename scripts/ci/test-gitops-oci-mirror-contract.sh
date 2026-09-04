#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal Terraform and workflow fragments intentionally contain $ expressions.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL GitOps OCI mirror contract: %s\n' "$*" >&2; exit 1; }

terraform_file="$root/infra/terraform/private-gitops.tf"
workflow="$root/.github/workflows/gitops-oci-mirror.yml"
allowlist="$root/.ci/gitops/approved-oci-artifacts.json"
dockerfile="$root/.ci/toolchains/gitops-oci-mirror.Dockerfile"
for file in "$terraform_file" "$workflow" "$allowlist" "$dockerfile"; do
  test -f "$file" || fail "missing required file: $file"
done

jq -e '.version == 1 and (.artifacts | type == "array") and all(.artifacts[]; (.source | type == "string") and (.destination | type == "string") and (.ecrTag | type == "string"))' "$allowlist" >/dev/null || fail 'approved artifact allowlist has an invalid schema'
grep -Fqx 'ENTRYPOINT ["skopeo"]' "$dockerfile" || fail 'mirror toolchain must invoke skopeo'
grep -Fq 'apt-get install -y --no-install-recommends ca-certificates skopeo' "$dockerfile" || fail 'mirror toolchain must include skopeo'

for required in \
  'variable "enable_private_gitops_foundation"' \
  'default     = true' \
  'resource "aws_ecr_repository" "private_gitops"' \
  'image_tag_mutability = "IMMUTABLE"' \
  'scan_on_push = true' \
  'prevent_destroy = true' \
  'resource "aws_iam_role" "github_gitops_oci_mirror"' \
  'token.actions.githubusercontent.com:repository' \
  'repo:${split("/", var.github_repository)[0]}@*/${split("/", var.github_repository)[1]}@*:environment:gitops-oci-mirror' \
  '"ecr:DescribeImages"' \
  '"ecr:PutImage"' \
  'github_gitops_oci_mirror_role_arn'; do
  grep -Fq "$required" "$terraform_file" || fail "Terraform contract omits: $required"
done

if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|PutLifecyclePolicy|\*)' "$terraform_file"; then
  fail 'mirror role exceeds the required ECR read-and-push permission boundary'
fi

for required in \
  'environment: gitops-oci-mirror' \
  'id-token: write' \
  'source must be an OCI reference pinned to a 64-character sha256 digest' \
  'reviewed GitOps artifact allowlist' \
  '.ci/gitops/approved-oci-artifacts.json' \
  'ECR_TAG=$ecr_tag' \
  'aws sts assume-role-with-web-identity' \
  'GITOPS_OCI_MIRROR_TOOL_IMAGE' \
  'copy --all "docker://$SOURCE" "docker://$destination_ref"' \
  'aws ecr describe-images' \
  'test "$destination_digest" = "$source_digest"' \
  'GITHUB_STEP_SUMMARY'; do
  grep -Fq "$required" "$workflow" || fail "workflow contract omits: $required"
done

if grep -Fq 'docker buildx imagetools create' "$workflow"; then
  fail 'workflow uses manifest-only imagetools instead of a blob-copying OCI client'
fi

grep -Fq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "$workflow" || fail 'workflow must read the versioned artifact approval allowlist'

printf 'PASS private GitOps OCI mirror accepts only approved digests and records the ECR-verified digest.\n'
