#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL ECR signer mirror contract: %s\n' "$*" >&2; exit 1; }

ecr_file="$root/infra/terraform/ecr-signer-mirror.tf"
signer_file="$root/infra/terraform/vault-signer.tf"
endpoints_file="$root/infra/terraform/endpoints.tf"
fixture="$root/infra/terraform/fixtures/offline-release-signer.tfvars"
workflow="$root/.github/workflows/ecr-signer-mirror.yml"
for file in "$ecr_file" "$signer_file" "$endpoints_file" "$fixture" "$workflow"; do
  test -f "$file" || fail "missing required file: $file"
done

for required in \
  'variable "enable_release_signer_ecr_mirror"' \
  'default     = false' \
  'resource "aws_ecr_repository" "release_signer"' \
  'image_tag_mutability = "IMMUTABLE"' \
  'encryption_type = "KMS"' \
  'scan_on_push = true' \
  'resource "aws_kms_key" "release_signer_ecr"' \
  'resource "aws_iam_role" "github_ecr_signer_mirror"' \
  "repo:\${var.github_repository}:environment:ecr-signer-mirror" \
  '"ecr:GetAuthorizationToken"' \
  '"ecr:BatchCheckLayerAvailability"' \
  '"ecr:CompleteLayerUpload"' \
  '"ecr:InitiateLayerUpload"' \
  '"ecr:PutImage"' \
  '"ecr:UploadLayerPart"'; do
  grep -Fq "$required" "$ecr_file" || fail "ECR mirror contract omits: $required"
done

if grep -Eq 'ecr:(DeleteRepository|DeleteImage|SetRepositoryPolicy|PutLifecyclePolicy|\*)' "$ecr_file"; then
  fail 'mirror role exceeds the required ECR push-only permission boundary'
fi

for required in \
  '"logs", "sts"' \
  'resource "aws_vpc_security_group_ingress_rule" "endpoints_https_from_release_signer"' \
  'referenced_security_group_id = aws_security_group.release_signer[0].id'; do
  grep -Fq "$required" "$endpoints_file" || fail "private endpoint path omits: $required"
done

for required in \
  'GetEcrAuthorizationToken' \
  'PullOnlyPrivateSignerImage' \
  'image_pull_credentials_type = "SERVICE_ROLE"' \
  '"ecr:BatchGetImage"' \
  '"ecr:GetDownloadUrlForLayer"' \
  'var.enable_release_signer_ecr_mirror' \
  "dkr\\\\.ecr\\\\.\${var.aws_region}\\\\.amazonaws\\\\.com/\${local.name_prefix}-vault-release-signer@sha256:"; do
  grep -Fq "$required" "$signer_file" || fail "CodeBuild ECR-only contract omits: $required"
done

grep -Fq 'enable_release_signer_ecr_mirror = true' "$fixture" || fail 'enabled offline fixture does not enable the ECR mirror foundation'
grep -Eq '^release_signer_image[[:space:]]*=[[:space:]]*"123456789012\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/node-operator-baseline-vault-release-signer@sha256:' "$fixture" || fail 'fixture is not a same-account private ECR digest'

for required in \
  'environment: ecr-signer-mirror' \
  'id-token: write' \
  'packages: read' \
  'ECR_SIGNER_MIRROR_ROLE_ARN' \
  "ghcr\\.io/s1ns3nz0/node-operator/vault-release-signer@sha256" \
  "destination_repository='node-operator-baseline-vault-release-signer'" \
  'docker push' \
  'describe-images'; do
  grep -Fq "$required" "$workflow" || fail "mirror workflow omits contract fragment: $required"
done

if grep -Eq '^[[:space:]]*packages:[[:space:]]*write' "$workflow" || grep -Fq 'ecr:*' "$workflow"; then
  fail 'mirror workflow requests broad package or ECR permission'
fi

printf 'PASS private ECR signer mirror, endpoint, and CodeBuild pull contracts are least-privilege and disabled by default.\n'
