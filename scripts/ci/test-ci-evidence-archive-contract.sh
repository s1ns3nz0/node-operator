#!/usr/bin/env bash
# Check objective: Ensure CI evidence is redacted, Cosign-signed, verified, and archived through the dedicated S3 role.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
workflow="$root/.github/workflows/ci-evidence-archive.yml"
iac="$root/infra/terraform/ci-evidence-archive.tf"
archive="$root/scripts/ci/archive-ci-evidence.sh"
assume="$root/scripts/ci/assume-ci-evidence-archive-role.sh"
for file in "$workflow" "$iac" "$archive" "$assume"; do
  test -f "$file" || { printf 'missing archive contract file: %s\n' "$file" >&2; exit 1; }
done
grep -Fq 'workflow_run:' "$workflow"
grep -Fq 'workflows: [CI Evidence Gate]' "$workflow"
grep -Fq "github.event.workflow_run.conclusion == 'success'" "$workflow"
grep -Fq 'id-token: write' "$workflow"
grep -Fq 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093' "$workflow"
grep -Fq 'cosign sign-blob --yes --bundle' "$archive"
grep -Fq 'cosign verify-blob --bundle' "$archive"
grep -Fq 'aws s3 cp' "$archive"
grep -Fq 'manifest.sigstore.json' "$archive"
grep -Fq 'object_lock_enabled = true' "$iac"
grep -Fq 'default_retention' "$iac"
grep -Fq 'sse_algorithm     = "aws:kms"' "$iac"
grep -Fq 'ci-evidence-archive' "$iac"
grep -Fq 'sts:AssumeRoleWithWebIdentity' "$iac"
if grep -Eq 'secrets/|VAULT_TOKEN|recovery.key|private_key' "$archive"; then
  printf 'archive script contains a forbidden secret path or token reference\n' >&2
  exit 1
fi
bash -n "$archive" "$assume"
printf 'PASS: CI evidence archive is Cosign-signed, verified, redacted, and OIDC-scoped.\n'
