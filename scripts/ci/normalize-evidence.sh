#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then printf 'usage: %s RAW_EVIDENCE_DIR COMMIT_SHA OUTPUT_JSON\n' "$0" >&2; exit 64; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"; raw_directory="$1"; commit_sha="$2"; output_path="$3"
require_command jq
[[ "$commit_sha" =~ ^[0-9a-f]{40}$ ]] || { printf 'commit SHA must be 40 lowercase hexadecimal characters\n' >&2; exit 64; }
for tool in gitleaks osv semgrep zizmor checkov; do
  source_path="$raw_directory/$tool.json"
  require_file "$source_path"
  jq -e --arg tool "$tool" --arg sha "$commit_sha" '
    .schema_version == "v1" and .tool == $tool and .commit_sha == $sha and
    (.collected_at | type == "string") and (.result | type == "object")
  ' "$source_path" >/dev/null || { printf 'invalid %s collector envelope\n' "$tool" >&2; exit 1; }
done
mkdir -p "$(dirname "$output_path")"
jq -n --arg sha "$commit_sha" --slurpfile tiers "$root/policy/data/tiers.json" --slurpfile exceptions "$root/policy/data/exceptions.json" \
  --slurpfile gitleaks "$raw_directory/gitleaks.json" --slurpfile osv "$raw_directory/osv.json" --slurpfile semgrep "$raw_directory/semgrep.json" \
  --slurpfile zizmor "$raw_directory/zizmor.json" --slurpfile checkov "$raw_directory/checkov.json" \
  '{subject:{commit_sha:$sha}, evidence:{gitleaks:$gitleaks[0].result, osv:$osv[0].result, semgrep:$semgrep[0].result, zizmor:$zizmor[0].result, checkov:$checkov[0].result}, policy:{tiers:$tiers[0], exceptions:$exceptions[0].exceptions}}' > "$output_path"
