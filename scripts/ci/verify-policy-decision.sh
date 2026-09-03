#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then printf 'usage: %s DECISION_JSON\n' "$0" >&2; exit 64; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
require_command jq; require_file "$1"
jq -e '.summary.block == 0' "$1" >/dev/null || { printf 'OPA policy blocked this subject\n' >&2; exit 1; }
