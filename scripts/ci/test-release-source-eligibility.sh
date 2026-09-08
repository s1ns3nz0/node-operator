#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fixtures intentionally write scripts with runtime variables.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/../.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"
sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

for workflow in ci-terraform.yml ci-policy.yml policy-foundation.yml; do
  grep -Fq 'pull_request:' "$root/.github/workflows/$workflow"
  grep -Fq 'branches: [main]' "$root/.github/workflows/$workflow"
done

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exit "${GIT_RESULT:-0}"' > "$temporary_directory/bin/git"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'for arg in "$@"; do case "$arg" in *commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/check-runs*) jq -c ".check_runs[]" "$SOURCE_CHECK_FIXTURE"; exit ;; *commits/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/check-runs*) jq -c ".check_runs[]" "$PR_CHECK_FIXTURE"; exit ;; *commits/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/pulls) cat "$PULL_FIXTURE"; exit ;; esac; done; exit 1' > "$temporary_directory/bin/gh"
chmod +x "$temporary_directory/bin/git" "$temporary_directory/bin/gh"
jq -n --arg sha "$sha" '
  ["quality","scanners","policy","terraform","policy-foundation"] |
  map({name:.,status:"completed",conclusion:"success",head_sha:$sha,app:{slug:"github-actions"},details_url:"https://github.com/owner/repo/actions/runs/123/job/456"}) |
  {total_count:length,check_runs:.}
' > "$temporary_directory/pass.json"
printf '%s\n' '{"total_count":1,"check_runs":[{"name":"CI Evidence Decision","status":"completed","conclusion":"success","head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","app":{"slug":"github-actions"},"details_url":"https://github.com/owner/repo/actions/runs/124"}]}' > "$temporary_directory/pr-check.json"
printf '%s\n' '[{"merged_at":"2026-09-08T00:00:00Z","base":{"ref":"main"},"head":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]' > "$temporary_directory/pulls.json"
SOURCE_CHECK_FIXTURE="$temporary_directory/pass.json" PR_CHECK_FIXTURE="$temporary_directory/pr-check.json" PULL_FIXTURE="$temporary_directory/pulls.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" >/dev/null

jq '(.check_runs[] | select(.name == "CI Evidence Decision") | .conclusion) = "failure"' "$temporary_directory/pr-check.json" > "$temporary_directory/fail.json"
if SOURCE_CHECK_FIXTURE="$temporary_directory/pass.json" PR_CHECK_FIXTURE="$temporary_directory/fail.json" PULL_FIXTURE="$temporary_directory/pulls.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a failed OPA evidence decision\n' >&2
  exit 1
fi
jq '(.check_runs[] | select(.name == "quality") | .app.slug) = "untrusted-app"' "$temporary_directory/pass.json" > "$temporary_directory/spoofed.json"
if SOURCE_CHECK_FIXTURE="$temporary_directory/spoofed.json" PR_CHECK_FIXTURE="$temporary_directory/pr-check.json" PULL_FIXTURE="$temporary_directory/pulls.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a check from an untrusted app\n' >&2
  exit 1
fi
if GIT_RESULT=1 SOURCE_CHECK_FIXTURE="$temporary_directory/pass.json" PR_CHECK_FIXTURE="$temporary_directory/pr-check.json" PULL_FIXTURE="$temporary_directory/pulls.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a source outside origin/main\n' >&2
  exit 1
fi
printf 'PASS: release eligibility requires main ancestry and exact-SHA trusted security checks.\n'
