#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then printf 'usage: %s REVIEW_EVENT_JSON\n' "$0" >&2; exit 64; fi
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
event="$1"

jq -e --arg repo "$GITHUB_REPOSITORY" '
  .workflow_run.name == "CI Evidence Review Signal" and
  .workflow_run.path == ".github/workflows/ci-review-refresh.yml" and
  .workflow_run.event == "pull_request_review" and
  .workflow_run.conclusion == "success" and
  .workflow_run.repository.full_name == $repo and
  (.workflow_run.pull_requests | type == "array" and length == 1) and
  (.workflow_run.pull_requests[0].number | type == "number")
' "$event" >/dev/null
pr_number="$(jq -r '.workflow_run.pull_requests[0].number' "$event")"
current_pr="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr_number")"
current_head="$(jq -er '.head.sha' <<<"$current_pr")"
[[ "$current_head" =~ ^[0-9a-f]{40}$ ]] || { printf 'current pull-request head is invalid\n' >&2; exit 1; }

runs="$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/ci-security.yml/runs?event=pull_request&per_page=100")"
run_id="$(jq -er --arg repo "$GITHUB_REPOSITORY" --arg sha "$current_head" --argjson pr "$pr_number" '
  [.workflow_runs[] | select(
    .repository.full_name == $repo and .path == ".github/workflows/ci-security.yml" and
    .event == "pull_request" and .head_sha == $sha and .status == "completed" and
    any(.pull_requests[]?; .number == $pr)
  )] | sort_by(.run_number) | reverse | select(length > 0) | .[0].id
' <<<"$runs")"
[[ "$run_id" =~ ^[1-9][0-9]*$ ]] || { printf 'trusted CI Security run ID is invalid\n' >&2; exit 1; }
gh api --method POST "repos/$GITHUB_REPOSITORY/actions/runs/$run_id/rerun" >/dev/null
printf 'requested trusted evidence refresh for PR %s head %s via CI Security run %s\n' "$pr_number" "$current_head" "$run_id"
