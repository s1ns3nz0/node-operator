#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
integrity="$root/.github/workflows/ci-release-integrity.yml"
release="$root/.github/workflows/release.yml"
grep -Fq 'workflow_call:' "$integrity"
grep -Fq 'uses: ./.github/workflows/ci-release-integrity.yml' "$release"
grep -Fq 'needs: reproducibility' "$release"
printf '%s\n' 'PASS: release publication is blocked on reusable reproducibility evidence.'
