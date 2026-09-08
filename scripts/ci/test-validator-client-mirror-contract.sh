#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
terraform_file="$root/infra/terraform/validator-client-ecr-mirror.tf"
workflow="$root/.github/workflows/validator-client-image-mirror.yml"
allowlist="$root/.ci/validator/approved-client-images.json"
for required in 'enable_validator_client_ecr_mirror' 'default     = false' 'aws_ecr_repository" "validator_client' 'image_tag_mutability = "IMMUTABLE"' 'encryption_type = "KMS"' 'scan_on_push = true' 'github_oidc_subject_prefix}:environment:validator-client-ecr-mirror' 'ecr:BatchGetImage' 'ecr:DescribeImages' 'ecr:PutImage'; do
  grep -Fq "$required" "$terraform_file" || { printf 'missing mirror contract: %s\n' "$required" >&2; exit 1; }
done
grep -Fq 'offchainlabs/prysm-validator@sha256:' "$workflow"
grep -Fq 'docker buildx imagetools create' "$workflow"
grep -Fq 'approved-client-images.json' "$workflow"
grep -Fq '::add-mask::' "$workflow"
grep -Fq 'persist-credentials: false' "$workflow"
# This verifies literal workflow shell source.
# shellcheck disable=SC2016
grep -Fq 'test "$digest" = "${SOURCE_IMAGE#*@}"' "$workflow"
jq -e '.schema_version == 1 and (.images | length == 1) and .images[0].approved == true and (.images[0].source | test("^offchainlabs/prysm-validator@sha256:[a-f0-9]{64}$")) and (.images[0].linux_amd64_manifest | test("^sha256:[a-f0-9]{64}$"))' "$allowlist" >/dev/null
if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|\*)' "$terraform_file"; then printf '%s\n' 'validator mirror grants destructive ECR permission' >&2; exit 1; fi
printf '%s\n' 'PASS: Prysm validator mirror is private, immutable, OIDC-bound, and push-only.'
