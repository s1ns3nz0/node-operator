#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fixtures intentionally write scripts with runtime variables.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"
sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exit "${GIT_RESULT:-0}"' > "$temporary_directory/bin/git"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'jq -c ".check_runs[]" "$CHECK_FIXTURE"' > "$temporary_directory/bin/gh"
chmod +x "$temporary_directory/bin/git" "$temporary_directory/bin/gh"
jq -n --arg sha "$sha" '
  ["quality","scanners","policy","terraform","policy-foundation","CI Evidence Decision"] |
  map({name:.,status:"completed",conclusion:"success",head_sha:$sha,app:{slug:"github-actions"},details_url:"https://github.com/owner/repo/actions/runs/123/job/456"}) |
  {total_count:length,check_runs:.}
' > "$temporary_directory/pass.json"
CHECK_FIXTURE="$temporary_directory/pass.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo source_sha="$sha" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" >/dev/null

jq '(.check_runs[] | select(.name == "CI Evidence Decision") | .conclusion) = "failure"' "$temporary_directory/pass.json" > "$temporary_directory/fail.json"
if CHECK_FIXTURE="$temporary_directory/fail.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo source_sha="$sha" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a failed OPA evidence decision\n' >&2
  exit 1
fi
jq '(.check_runs[] | select(.name == "quality") | .app.slug) = "untrusted-app"' "$temporary_directory/pass.json" > "$temporary_directory/spoofed.json"
if CHECK_FIXTURE="$temporary_directory/spoofed.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo source_sha="$sha" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a check from an untrusted app\n' >&2
  exit 1
fi
if GIT_RESULT=1 CHECK_FIXTURE="$temporary_directory/pass.json" GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo source_sha="$sha" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/verify-release-source-eligibility.sh" "$sha" 2>/dev/null; then
  printf 'eligibility accepted a source outside origin/main\n' >&2
  exit 1
fi
printf 'PASS: release eligibility requires main ancestry and exact-SHA trusted security checks.\n'
