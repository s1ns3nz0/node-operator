#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow="$script_dir/../../.github/workflows/ci-security.yml"
gate_workflow="$script_dir/../../.github/workflows/opa-pr-gate.yml"

# The scanner produces the sole uploadable evidence in a non-hidden directory,
# rather than a hidden checkout path. This preserves upload-artifact's safe
# default (hidden files excluded) and prevents an accidental workspace-wide
# upload. The scanner mounts the workspace read-only and /evidence separately.
grep -Fq 'EVIDENCE_ROOT: ${{ github.workspace }}/security-evidence' "$workflow"
grep -Fq 'path: ${{ env.EVIDENCE_ROOT }}' "$workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE:/workspace:ro"' "$workflow"
grep -Fq -- '--volume "$EVIDENCE_ROOT:/evidence"' "$workflow"
if grep -Fq 'include-hidden-files: true' "$workflow"; then
  printf 'security evidence upload must not include hidden files\n' >&2
  exit 1
fi

test "$(grep -Fc 'checks: write' "$gate_workflow")" -eq 2
grep -Fq 'resolve-pr-evidence-context.sh' "$gate_workflow"
grep -Fq 'ref: ${{ steps.context.outputs.trusted_sha }}' "$gate_workflow"
grep -Fq 'Collect trusted security evidence from untrusted source' "$gate_workflow"
grep -Fq -- '--volume "$GITHUB_WORKSPACE/.pr-source:/workspace:ro"' "$gate_workflow"
grep -Fq -- '--volume "$RUNNER_TEMP/head-security-evidence:/evidence"' "$gate_workflow"
if grep -Fq 'Download scanner evidence from the completed PR run' "$gate_workflow"; then
  printf 'trusted decision must not consume a pull-request-controlled scanner artifact\n' >&2
  exit 1
fi
grep -Fq 'Publish exact-SHA evidence check' "$gate_workflow"
grep -Fq 'Publish failed exact-SHA evidence check' "$gate_workflow"
grep -Fq 'publish-pr-evidence-check.sh "$SUBJECT_SHA"' "$gate_workflow"

printf 'PASS: scanner evidence is confined to a non-hidden dedicated directory.\n'
