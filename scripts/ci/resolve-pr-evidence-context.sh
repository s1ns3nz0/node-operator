#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  printf 'usage: %s EVENT_JSON GITHUB_OUTPUT\n' "$0" >&2
  exit 64
fi
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TRUSTED_WORKFLOW_SHA:?TRUSTED_WORKFLOW_SHA is required}"
event="$1"
output="$2"

jq -e --arg repo "$GITHUB_REPOSITORY" '
  .workflow_run.event == "pull_request" and
  ((.workflow_run.name == "CI Security" and .workflow_run.path == ".github/workflows/ci-security.yml") or
   (.workflow_run.name == "CI" and .workflow_run.path == ".github/workflows/ci.yml")) and
  .workflow_run.repository.full_name == $repo and
  (.workflow_run.head_sha | test("^[0-9a-f]{40}$")) and
  (.workflow_run.pull_requests | type == "array" and length == 1) and
  (.workflow_run.pull_requests[0].number | type == "number")
' "$event" >/dev/null

subject_sha="$(jq -r '.workflow_run.head_sha' "$event")"
pr_number="$(jq -r '.workflow_run.pull_requests[0].number' "$event")"
current_head="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr_number" --jq '.head.sha')"
[ "$current_head" = "$subject_sha" ] || { printf 'pull-request head changed after scanner run\n' >&2; exit 1; }
trusted_sha="$TRUSTED_WORKFLOW_SHA"
[[ "$trusted_sha" =~ ^[0-9a-f]{40}$ ]] || { printf 'trusted policy revision is invalid\n' >&2; exit 1; }
printf 'subject_sha=%s\npr_number=%s\ntrusted_sha=%s\n' "$subject_sha" "$pr_number" "$trusted_sha" >> "$output"
