#!/usr/bin/env bash
# Check objective: Publish a fail-closed review decision only while the PR still matches the cached head and base.
set -euo pipefail
current="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")"
jq -e --arg sha "$SUBJECT_SHA" '.state == "open" and .head.sha == $sha' <<<"$current" >/dev/null || {
  printf 'PR head changed; refusing to publish an obsolete review check.\n' >&2
  exit 1
}
decision=-
if [ "${EVALUATION_RESULT:-}" = success ] && [ -f "$EVIDENCE_ROOT/published/decision.json" ] && [ -f "$EVIDENCE_ROOT/cache/cache-context.json" ]; then
  base="$(jq -er .base_sha "$EVIDENCE_ROOT/cache/cache-context.json")"
  if jq -e --arg base "$base" '.base.sha == $base' <<<"$current" >/dev/null; then
    decision="$EVIDENCE_ROOT/published/decision.json"
  fi
fi
scripts/ci/publish-pr-evidence-check.sh "$SUBJECT_SHA" "$decision" "$DETAILS_URL"
if [ "$decision" = - ]; then
  printf 'Reusable evidence unavailable or stale; rerun CI to trigger fresh full CI Evidence Gate verification.\n' >&2
  exit 1
fi
scripts/ci/verify-policy-decision.sh "$decision"
