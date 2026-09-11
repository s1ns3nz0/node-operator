#!/usr/bin/env bash
# Check objective: Enforce the inlined release reproducibility gate and exact-SBOM SCA contracts.
# shellcheck disable=SC2016 # The workflow contract must match the literal GitHub runner variable.
set -euo pipefail
# shellcheck source=scripts/ci/lib/workflow-contract.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflow-contract.sh"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
release="$root/.github/workflows/release.yml"
reproducibility="$(workflow_job_source "$release" reproducibility)"
if grep -Fq 'uses: ./.github/workflows/ci-release-integrity.yml' "$release"; then
  printf 'release reproducibility must be inlined rather than call the retired reusable workflow\n' >&2
  exit 1
fi
grep -Fq 'needs: eligibility' <<<"$reproducibility"
grep -Fq 'verify-release-source-eligibility.sh "$GITHUB_SHA"' "$release"
grep -Fq 'needs: [eligibility, reproducibility]' "$release"
grep -Fq "inputs.mode == 'verify-only'" <<<"$reproducibility"
grep -Fq '!cancelled()' <<<"$reproducibility"
grep -Fq 'test-build-release-bundle.sh /output/current' <<<"$reproducibility"
grep -Fq 'install-release-sca-tool.sh "$RUNNER_TEMP/release-sca-bin"' <<<"$reproducibility"
grep -Fq 'scan-release-sbom.sh' <<<"$reproducibility"
grep -Fq 'sbom.cyclonedx.json' <<<"$reproducibility"
grep -Fq '.findings.critical == 0 and .findings.high == 0 and .findings.unknown == 0' <<<"$reproducibility"
grep -Fq 'artifact_digest: ${{ steps.sca-binding.outputs.artifact_digest }}' <<<"$reproducibility"
grep -Fq 'APPROVED_ARTIFACT_DIGEST: ${{ needs.reproducibility.outputs.artifact_digest }}' "$release"
grep -Fq 'sha256sum "$RUNNER_TEMP/release/node-operator-release-bundle.tar"' <(workflow_source "$release")
grep -Fq "jq -er '.metadata.component.version'" <(workflow_source "$release")
printf '%s\n' 'PASS: release publication is blocked on the inlined reproducibility and exact-SBOM SCA gate.'
