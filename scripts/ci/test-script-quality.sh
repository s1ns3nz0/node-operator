#!/usr/bin/env bash
# Check objective: Enforce ShellCheck static analysis of CI and release shell scripts.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
require_command shellcheck
find "$root/scripts/ci" "$root/scripts/release" -type f -name '*.sh' -exec shellcheck -x -P "$root/scripts/ci" {} +
