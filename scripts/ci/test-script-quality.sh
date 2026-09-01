#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
require_command shellcheck
find "$root/scripts/ci" -type f -name '*.sh' -exec shellcheck -x -P "$root/scripts/ci" {} +
