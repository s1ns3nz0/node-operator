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
grep -Fq '.mirror_eligible == true and .release_channel == "upstream-mirror" and .provenance_status == "upstream-release-mirror"' "$workflow"
grep -Fq '::add-mask::' "$workflow"
grep -Fq 'persist-credentials: false' "$workflow"
# This verifies literal workflow shell source.
# shellcheck disable=SC2016
grep -Fq 'test "$digest" = "${SOURCE_IMAGE#*@}"' "$workflow"
jq -e '
  .schema_version == 2 and (.images | length == 2) and
  ([.images[] | select(.release_channel == "upstream-mirror" and .mirror_eligible == true and .provenance_status == "upstream-release-mirror")] | length == 1) and
  ([.images[] | select(.release_channel == "manual-native-mtls" and .mirror_eligible == false and .provenance_status == "manual-reviewed-not-ci-attested" and .stage_approved == true and .activation_approved == true and (.approval_basis | type == "object"))] | length == 1) and
  all(.images[]; (.private_image | test("^106760547719\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/node-operator-baseline-validator-prysm@sha256:[a-f0-9]{64}$")))
' "$allowlist" >/dev/null
if jq -e '[.images[] | select(.mirror_eligible == true and .release_channel == "upstream-mirror")] | any(.provenance_status == "manual-reviewed-not-ci-attested")' "$allowlist" >/dev/null; then
  printf '%s\n' 'manual native record is mirror-eligible' >&2; exit 1
fi
if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|\*)' "$terraform_file"; then printf '%s\n' 'validator mirror grants destructive ECR permission' >&2; exit 1; fi
printf '%s\n' 'PASS: Prysm validator mirror is private, immutable, OIDC-bound, and push-only.'
