#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
terraform_file="$root/infra/terraform/validator-client-ecr-mirror.tf"
workflow="$root/.github/workflows/validator-client-image-mirror.yml"
for required in 'enable_validator_client_ecr_mirror' 'default     = false' 'aws_ecr_repository" "validator_client' 'image_tag_mutability = "IMMUTABLE"' 'encryption_type = "KMS"' 'scan_on_push = true' 'environment:validator-client-ecr-mirror' 'ecr:PutImage'; do
  grep -Fq "$required" "$terraform_file" || { printf 'missing mirror contract: %s\n' "$required" >&2; exit 1; }
done
grep -Fq 'offchainlabs/prysm-validator@sha256:' "$workflow"
grep -Fq 'docker buildx imagetools create' "$workflow"
if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|\*)' "$terraform_file"; then printf '%s\n' 'validator mirror grants destructive ECR permission' >&2; exit 1; fi
printf '%s\n' 'PASS: Prysm validator mirror is private, immutable, OIDC-bound, and push-only.'
