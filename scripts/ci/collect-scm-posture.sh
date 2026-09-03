#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then printf 'usage: %s COMMIT_SHA OUTPUT_JSON\n' "$0" >&2; exit 64; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
commit_sha="$1"; output_path="$2"
[[ "$commit_sha" =~ ^[0-9a-f]{40}$ ]] || { printf 'commit SHA must be 40 lowercase hexadecimal characters\n' >&2; exit 64; }
require_command gh; require_command jq; require_file "${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is required}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
number="$(jq -er '.pull_request.number' "$GITHUB_EVENT_PATH")"
author="$(jq -er '.pull_request.user.login' "$GITHUB_EVENT_PATH")"
event_head="$(jq -er '.pull_request.head.sha' "$GITHUB_EVENT_PATH")"
[ "$event_head" = "$commit_sha" ] || { printf 'event head SHA does not match evidence subject\n' >&2; exit 1; }
temporary_directory="$(mktemp -d)"; trap 'rm -rf "$temporary_directory"' EXIT
gh api --paginate "repos/$repository/pulls/$number/files?per_page=100" > "$temporary_directory/files.json"
gh api --paginate "repos/$repository/pulls/$number/reviews?per_page=100" > "$temporary_directory/reviews.json"
mkdir -p "$(dirname "$output_path")"
jq -n --arg author "$author" --arg head "$commit_sha" --slurpfile files "$temporary_directory/files.json" --slurpfile reviews "$temporary_directory/reviews.json" '
  {changed_files:([$files[][]? | .filename] | unique), pull_request:{author:$author, head_sha:$head}, approvers:([$reviews[][]? | select(.state == "APPROVED" and .commit_id == $head) | .user.login] | unique)}' > "$output_path"
