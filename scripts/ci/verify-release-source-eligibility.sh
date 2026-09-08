#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s SOURCE_SHA\n' "$0" >&2
  exit 64
fi
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
source_sha="$1"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { printf 'source SHA must be 40 lowercase hexadecimal characters\n' >&2; exit 64; }
git merge-base --is-ancestor "$source_sha" refs/remotes/origin/main || { printf 'release source is not reachable from origin/main\n' >&2; exit 1; }

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
checks="$temporary_directory/checks.json"
gh api --paginate -H 'Accept: application/vnd.github+json' \
  "repos/$GITHUB_REPOSITORY/commits/$source_sha/check-runs?filter=latest&per_page=100" \
  --jq '.check_runs[]' | jq -s . > "$checks"

for required in quality scanners policy terraform policy-foundation 'CI Evidence Decision'; do
  jq -e --arg name "$required" --arg repo "$GITHUB_REPOSITORY" --arg sha "$source_sha" '
    [.[] | select(
      .name == $name and
      .status == "completed" and
      .conclusion == "success" and
      .head_sha == $sha and
      .app.slug == "github-actions" and
      (.details_url | type == "string" and startswith("https://github.com/" + $repo + "/actions/runs/"))
    )] | length == 1
  ' "$checks" >/dev/null || { printf 'required trusted check is absent or ambiguous: %s\n' "$required" >&2; exit 1; }
done
printf 'PASS: release source %s has the complete trusted security decision set.\n' "$source_sha"
