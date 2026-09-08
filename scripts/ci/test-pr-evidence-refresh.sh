#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fake gh expands fixture variables at execution time.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"
cat > "$temporary_directory/event.json" <<EOF
{"workflow_run":{"name":"CI Evidence Review Signal","path":".github/workflows/ci-review-refresh.yml","event":"pull_request_review","conclusion":"success","repository":{"full_name":"owner/repo"},"pull_requests":[{"number":7}]}}
EOF
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' '
printf "%s\n" "$*" >> "$GH_CALLS"
case "$*" in
  *"repos/owner/repo/pulls/7") printf "%s\n" "{\"head\":{\"sha\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}" ;;
  *"actions/workflows/ci-security.yml/runs"*) cat "$RUNS_FIXTURE" ;;
  *"actions/runs/321/rerun") exit 0 ;;
  *) exit 1 ;;
esac' > "$temporary_directory/bin/gh"
chmod +x "$temporary_directory/bin/gh"
printf '%s\n' '{"workflow_runs":[{"id":321,"run_number":9,"status":"completed","event":"pull_request","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":".github/workflows/ci-security.yml","repository":{"full_name":"owner/repo"},"pull_requests":[{"number":7}]}]}' > "$temporary_directory/runs.json"
GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo GH_CALLS="$temporary_directory/calls" RUNS_FIXTURE="$temporary_directory/runs.json" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/request-pr-evidence-refresh.sh" "$temporary_directory/event.json" >/dev/null
grep -Fq 'actions/runs/321/rerun' "$temporary_directory/calls"

jq '.workflow_run.path = ".github/workflows/untrusted.yml"' "$temporary_directory/event.json" > "$temporary_directory/stale.json"
if GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo GH_CALLS="$temporary_directory/stale-calls" RUNS_FIXTURE="$temporary_directory/runs.json" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/request-pr-evidence-refresh.sh" "$temporary_directory/stale.json" 2>/dev/null; then
  printf 'review refresher accepted the wrong signal workflow\n' >&2
  exit 1
fi
jq '.workflow_runs[0].head_sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$temporary_directory/runs.json" > "$temporary_directory/wrong-runs.json"
if GH_TOKEN=fixture GITHUB_REPOSITORY=owner/repo GH_CALLS="$temporary_directory/wrong-calls" RUNS_FIXTURE="$temporary_directory/wrong-runs.json" PATH="$temporary_directory/bin:$PATH" \
  "$script_dir/request-pr-evidence-refresh.sh" "$temporary_directory/event.json" 2>/dev/null; then
  printf 'review refresher accepted a scanner run for another head\n' >&2
  exit 1
fi
printf 'PASS: review refresh reruns only exact-head trusted CI Security evidence.\n'
