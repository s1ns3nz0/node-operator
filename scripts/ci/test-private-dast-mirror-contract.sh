#!/usr/bin/env bash
# Check objective: Verify private DAST mirror uses the approved scanner digest and restricted publication path.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for file in \
  "$root/infra/terraform/private-dast-ecr.tf" \
  "$root/.github/workflows/private-dast-image-mirror.yml" \
  "$root/scripts/ci/verify-private-dast-scanner.sh" \
  "$root/scripts/ci/assume-private-dast-mirror-role.sh" \
  "$root/scripts/ci/mirror-private-dast-scanner.sh"; do test -f "$file"; done
bash "$root/scripts/ci/verify-private-dast-scanner.sh" "$root/.ci/dast/approved-scanner.json" >/dev/null
for required in 'image_tag_mutability = "IMMUTABLE"' 'encryption_type = "KMS"' 'scan_on_push = true' 'private-dast-ecr-mirror' 'ecr:PutImage'; do grep -Fq "$required" "$root/infra/terraform/private-dast-ecr.tf"; done
grep -Fq 'workflow_dispatch:' "$root/.github/workflows/private-dast-image-mirror.yml"
grep -Fq 'id-token: write' "$root/.github/workflows/private-dast-image-mirror.yml"
printf 'PASS: private DAST scanner mirror is immutable, allowlisted, and OIDC-scoped.\n'
