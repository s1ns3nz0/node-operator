#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
temporary_directory="$(mktemp -d)"; trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"
printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in *files*) printf "%s\n" "[{\"filename\":\"policy/decision.rego\"}]" ;; *reviews*) printf "%s\n" "[{\"state\":\"APPROVED\",\"commit_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"user\":{\"login\":\"fjybjinsu\"}}]" ;; *) exit 64 ;; esac' > "$temporary_directory/bin/gh"
chmod +x "$temporary_directory/bin/gh"
printf '%s\n' '{"pull_request":{"number":1,"user":{"login":"author"},"head":{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}}' > "$temporary_directory/event.json"
PATH="$temporary_directory/bin:$PATH" GITHUB_EVENT_PATH="$temporary_directory/event.json" GITHUB_REPOSITORY="owner/repo" "$script_dir/collect-scm-posture.sh" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$temporary_directory/scm.json"
jq -e '.changed_files == ["policy/decision.rego"] and .pull_request.head_sha == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and .approvers == ["fjybjinsu"]' "$temporary_directory/scm.json" >/dev/null
