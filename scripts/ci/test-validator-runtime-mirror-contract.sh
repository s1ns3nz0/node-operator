#!/usr/bin/env bash
# Check objective: Enforce digest-pinned validator runtime mirror allowlist and publisher constraints.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$root/scripts/ci/lib/workflow-contract.sh"
terraform_file="$root/infra/terraform/validator-runtime-ecr-mirror.tf"
workflow="$root/.github/workflows/validator-runtime-image-mirror.yml"
allowlist="$root/.ci/validator/approved-runtime-images.json"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for required in 'enable_validator_runtime_ecr_mirror' 'default     = false' 'aws_ecr_repository" "validator_runtime' 'image_tag_mutability = "IMMUTABLE"' 'encryption_type = "KMS"' 'scan_on_push = true' 'github_oidc_subject_prefix}:environment:validator-runtime-ecr-mirror' 'ecr:BatchGetImage' 'ecr:DescribeImages' 'ecr:PutImage'; do
  grep -Fq "$required" "$terraform_file" || fail "missing runtime mirror contract: $required"
done
grep -Fq 'validator-runtime-web3signer' "$terraform_file" || fail 'runtime mirror can collide with the legacy Web3Signer repository'
grep -Fq 'validator-runtime-postgres' "$terraform_file" || fail 'runtime mirror can collide with the legacy PostgreSQL repository'
grep -Fq 'approved-runtime-images.json' <(workflow_source "$workflow") || fail 'workflow does not use committed allowlist'
grep -Fq 'docker buildx imagetools create' <(workflow_source "$workflow") || fail 'workflow does not mirror source manifests'
grep -Fq 'ECR digest differs from reviewed source digest' <(workflow_source "$workflow") || fail 'workflow does not verify destination digest identity'
grep -Fq 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "$workflow" || fail 'workflow action is not pinned'
jq -e '
  .schema_version == 1 and
  (.images.web3signer.source | test("^consensys/web3signer@sha256:[a-f0-9]{64}$")) and
  (.images.postgres.source | test("^postgres@sha256:[a-f0-9]{64}$")) and
  ([.images[].source] | length == (unique | length))
' "$allowlist" >/dev/null || fail 'runtime image allowlist is invalid'
if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|\*)' "$terraform_file"; then fail 'runtime mirror grants destructive ECR permission'; fi
printf '%s\n' 'PASS: validator runtime mirror is allowlisted, private, immutable, OIDC-bound, and push-only.'
