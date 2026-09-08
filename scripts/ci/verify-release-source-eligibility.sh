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
fetch_checks() {
  local sha="$1" destination="$2"
  gh api --paginate -H 'Accept: application/vnd.github+json' \
    "repos/$GITHUB_REPOSITORY/commits/$sha/check-runs?filter=latest&per_page=100" \
    --jq '.check_runs[]' | jq -s . > "$destination"
}
trusted_check_present() {
  local input="$1" name="$2" sha="$3"
  jq -e --arg name "$name" --arg repo "$GITHUB_REPOSITORY" --arg sha "$sha" '
    [.[] | select(
      .name == $name and .status == "completed" and .conclusion == "success" and .head_sha == $sha and
      .app.slug == "github-actions" and
      (.details_url | type == "string" and startswith("https://github.com/" + $repo + "/actions/runs/"))
    )] | length == 1
  ' "$input" >/dev/null
}
fetch_checks "$source_sha" "$checks"

for required in quality scanners policy terraform policy-foundation; do
  trusted_check_present "$checks" "$required" "$source_sha" || { printf 'required trusted source check is absent or ambiguous: %s\n' "$required" >&2; exit 1; }
done

pulls="$temporary_directory/pulls.json"
gh api -H 'Accept: application/vnd.github+json' "repos/$GITHUB_REPOSITORY/commits/$source_sha/pulls" > "$pulls"
jq -e 'type == "array" and ([.[] | select(.merged_at != null and .base.ref == "main")] | length == 1)' "$pulls" >/dev/null || {
  printf 'release source must map to exactly one merged main pull request\n' >&2
  exit 1
}
pr_head_sha="$(jq -er '[.[] | select(.merged_at != null and .base.ref == "main")][0].head.sha | select(test("^[0-9a-f]{40}$"))' "$pulls")"
pr_checks="$temporary_directory/pr-checks.json"
fetch_checks "$pr_head_sha" "$pr_checks"
trusted_check_present "$pr_checks" 'CI Evidence Decision' "$pr_head_sha" || {
  printf 'merged pull-request head lacks the trusted CI Evidence Decision\n' >&2
  exit 1
}
printf 'PASS: release source %s has the complete trusted security decision set.\n' "$source_sha"
