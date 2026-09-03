#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL CodeBuild release activation: %s\n' "$*" >&2; exit 1; }

terraform_file="$root/infra/terraform/vault-signer.tf"
workflow="$root/.github/workflows/release.yml"
contract="$root/docs/gitops/codebuild-signing-input-contract.md"
for file in "$terraform_file" "$workflow" "$contract"; do
  test -f "$file" || fail "missing required file: $file"
done

terraform_project="$(awk '
  /^resource "aws_codebuild_project" "release_signer" \{/ { in_project=1 }
  in_project { print }
  in_project && /^}$/ { exit }
' "$terraform_file")"
test -n "$terraform_project" || fail 'release signer CodeBuild project is missing'

for required in \
  'variable "release_signer_image"' \
  'default     = ""' \
  'ghcr\\.io/' \
  '@sha256:' \
  'image           = var.release_signer_image' \
  'subnets            = var.release_signer_subnet_ids' \
  'length(var.release_signer_subnet_ids) > 0' \
  'source-location-must-be-overridden.zip' \
  'buildspec = "buildspec-release-sign.yml"' \
  'path                = "release-signer-output"' \
  'name                = "release-signer-output.zip"' \
  'namespace_type      = "BUILD_ID"' \
  'packaging           = "ZIP"'; do
  grep -Fq "$required" "$terraform_file" || fail "Terraform omits required signer guard or contract field: $required"
done

printf '%s\n' "$terraform_project" | grep -Fq 'type      = "S3"' || fail 'CodeBuild source must remain S3'
printf '%s\n' "$terraform_project" | grep -Fq 'encryption_disabled = false' || fail 'CodeBuild output must remain encrypted'
if printf '%s\n' "$terraform_project" | grep -Eq 'aws/codebuild/standard|bootstrap\.zip|aws_subnet\.private'; then
  fail 'CodeBuild project retains a public standard-image fallback, bootstrap input, or implicit subnet selection'
fi

for required in \
  'input_archive="$RUNNER_TEMP/${GITHUB_SHA}.zip"' \
  'input_key="release-input/sha256/${GITHUB_SHA}.zip"' \
  'buildspec-release-sign.yml' \
  'node-operator-release-bundle.tar' \
  'node-operator-release-bundle.sha256' \
  'provenance-input.json' \
  'aws s3api put-object' \
  "--if-none-match '*'" \
  '--source-version "$source_revision"' \
  '--source-location-override "${INPUT_BUCKET}/${input_key}"' \
  'release-verification.json' \
  'scripts/ci/verify-release-signature.sh "$signer_output"' \
  'release-signer-output.zip'; do
  grep -Fq -- "$required" "$workflow" || fail "release workflow omits required immutable signer boundary: $required"
done

if grep -Eq 'release-input/\$\{?GITHUB_SHA\}?\.zip|signature\.json|verify\.json' "$workflow"; then
  fail 'release workflow retains a legacy source key or raw Transit response consumption'
fi

# The workflow uses only a short-lived STS response. Literal access keys,
# secret values, Vault tokens, and public Vault URLs are prohibited here.
if grep -Eq 'AKIA[0-9A-Z]{16}|(?i:aws_secret_access_key)[[:space:]]*:|(?i:vault_token)[[:space:]]*:|https?://[^"[:space:]]*(vault|8200)' "$workflow" "$terraform_file"; then
  fail 'activation code introduces static credentials or a public Vault endpoint'
fi

for required in \
  'implemented code contract' \
  'enable_release_signer=false' \
  'release_signer_image=""' \
  'If-None-Match: *' \
  'release-signer-output.zip' \
  'lowercase `ghcr.io/...@sha256:<digest>`' \
  'No static credentials, raw Transit response artifacts, or public Vault'; do
  grep -Fq "$required" "$contract" || fail "contract does not document activation state: $required"
done

printf 'PASS CodeBuild signer activation is digest-pinned, source-immutable, output-gated, and disabled by default.\n'
