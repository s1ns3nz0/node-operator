#!/usr/bin/env bash
# Check objective: Reevaluate trusted cached findings against live SCM posture without invoking scanners or Terraform.
set -euo pipefail
scripts/ci/collect-scm-posture.sh "$SUBJECT_SHA" "$EVIDENCE_ROOT/scm.json" "$PR_NUMBER"
jq --slurpfile scm "$EVIDENCE_ROOT/scm.json" --slurpfile tiers policy/data/tiers.json \
  --slurpfile exceptions policy/data/exceptions.json \
  '.scm = $scm[0] | .policy = {tiers:$tiers[0],exceptions:$exceptions[0].exceptions}' \
  "$EVIDENCE_ROOT/cache/evidence.json" > "$EVIDENCE_ROOT/evidence.json"
status=0
scripts/ci/evaluate-policy.sh "$EVIDENCE_ROOT/evidence.json" "$EVIDENCE_ROOT/decision.json" || status=$?
scripts/ci/publish-evidence.sh "$EVIDENCE_ROOT/evidence.json" "$EVIDENCE_ROOT/decision.json" "$EVIDENCE_ROOT/published"
cp "$EVIDENCE_ROOT/cache/cache-context.json" "$EVIDENCE_ROOT/published/cache-context.json"
exit "$status"
