#!/usr/bin/env bash
# Purpose: The sole public deployment entrypoint for the downloaded release.
# Inputs: No command-line options; the interactive flow asks only for required
# non-secret values and ceremony inputs at the appropriate boundary.
# Outputs: A complete Hoodi validator deployment or a resumable private handoff.
# Side effects: The same guarded release flow provisions infrastructure, private
# access, Vault, workloads, custody and activation in dependency order.
set -euo pipefail
[ "$#" -eq 0 ] || { printf '%s\n' 'This is the sole release entrypoint and accepts no command-line options. Run it without arguments.' >&2; exit 64; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/interactive-hoodi-release.sh"
