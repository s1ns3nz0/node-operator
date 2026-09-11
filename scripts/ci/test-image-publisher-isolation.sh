#!/usr/bin/env bash
# Check objective: Ensure image publishers have isolated, digest-scoped permissions and release paths.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root/scripts/ci/lib/workflow-contract.sh"

for workflow in scanner-image-release.yml toolchain-image-release.yml; do
  file="$root/.github/workflows/$workflow"
  grep -Eq '^  build:$' "$file"
  grep -Eq '^      packages: read$' "$file"
  grep -Eq '^  publish:$' "$file"
  grep -Eq '^      packages: write$' "$file"
  grep -Fq "github.ref == 'refs/heads/main'" "$file"
  grep -Fq 'docker save --output' <(workflow_source "$file")
  grep -Fq 'docker load --input' <(workflow_source "$file")
  grep -Fq 'retention-days: 1' "$file"
done

grep -Fq 'io.node-operator.scanner-input-sha' <(workflow_source "$root/.github/workflows/scanner-image-release.yml")
grep -Fq 'io.node-operator.toolchain-input-sha' <(workflow_source "$root/.github/workflows/toolchain-image-release.yml")
