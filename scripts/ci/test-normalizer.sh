#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
"$script_dir/normalize-evidence.sh" "$root/policy/tests/fixtures/raw-evidence/clean" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$temporary_directory/normalized.json"
jq -e '.evidence.gitleaks.findings == [] and .policy.exceptions == []' "$temporary_directory/normalized.json" >/dev/null
if "$script_dir/normalize-evidence.sh" "$root/policy/tests/fixtures/raw-evidence/incomplete" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$temporary_directory/incomplete.json"; then printf 'incomplete evidence fixture unexpectedly normalized\n' >&2; exit 1; fi
