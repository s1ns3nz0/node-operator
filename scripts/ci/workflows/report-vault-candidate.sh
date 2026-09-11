#!/usr/bin/env bash
# Check objective: Report scan-only outcome.
set -euo pipefail

echo '### Frozen candidate verification (not a release or deployment)' >> "$GITHUB_STEP_SUMMARY"
if test -s "$RUNNER_TEMP/vault-runtime-evidence/scan-summary.json"; then
  jq '{artifact_digest,status,findings,build_provenance,deployment_authorized}' "$RUNNER_TEMP/vault-runtime-evidence/scan-summary.json" >> "$GITHUB_STEP_SUMMARY"
else
  echo 'Verification incomplete; not eligible for release.' >> "$GITHUB_STEP_SUMMARY"
fi
if test -s "$RUNNER_TEMP/vault-runtime-evidence/applicability-decision.json"; then
  echo 'Separate exact-candidate applicability decision (raw scan above is unchanged):' >> "$GITHUB_STEP_SUMMARY"
  cat "$RUNNER_TEMP/vault-runtime-evidence/applicability-decision.json" >> "$GITHUB_STEP_SUMMARY"
fi
