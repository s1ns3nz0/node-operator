#!/usr/bin/env bash
# Check objective: Enforce reusable release-integrity workflow and reproducibility gate contracts.
# shellcheck disable=SC2016 # The workflow contract must match the literal GitHub runner variable.
set -euo pipefail
# shellcheck source=scripts/ci/lib/workflow-contract.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflow-contract.sh"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
integrity="$root/.github/workflows/ci-release-integrity.yml"
release="$root/.github/workflows/release.yml"
grep -Fq 'workflow_call:' "$integrity"
if grep -Fq "tags: ['v*.*.*']" "$integrity"; then
  printf 'reusable integrity workflow must not also run independently for release tags\n' >&2
  exit 1
fi
grep -Fq 'uses: ./.github/workflows/ci-release-integrity.yml' "$release"
grep -Fq 'needs: eligibility' "$release"
grep -Fq 'verify-release-source-eligibility.sh "$GITHUB_SHA"' "$release"
grep -Fq 'needs: [eligibility, reproducibility]' "$release"
grep -Fq 'test-build-release-bundle.sh /output/current' "$integrity"
grep -Fq 'install-release-sca-tool.sh "$RUNNER_TEMP/release-sca-bin"' "$integrity"
grep -Fq 'scan-release-sbom.sh' "$integrity"
grep -Fq 'sbom.cyclonedx.json' "$integrity"
grep -Fq '.findings.critical == 0 and .findings.high == 0 and .findings.unknown == 0' "$integrity"
grep -Fq 'value: ${{ jobs.reproducibility.outputs.artifact_digest }}' "$integrity"
grep -Fq 'APPROVED_ARTIFACT_DIGEST: ${{ needs.reproducibility.outputs.artifact_digest }}' "$release"
grep -Fq 'sha256sum "$RUNNER_TEMP/release/node-operator-release-bundle.tar"' <(workflow_source "$release")
grep -Fq "jq -er '.metadata.component.version'" <(workflow_source "$release")
printf '%s\n' 'PASS: release publication is blocked on one reusable reproducibility and exact-SBOM SCA gate.'
