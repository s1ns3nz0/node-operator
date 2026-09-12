#!/usr/bin/env bash
# Purpose: Enter guarded discovery, infrastructure execution and separate SSM plan/apply.
# Inputs: start/status/resume options, downloaded release assets and explicit target profile.
# Outputs: Non-secret local checkpoint and readiness status, never a false deployment success.
# Side effects: Local writes and AWS reads; infrastructure/SSM apply provisions only after separate terminal confirmation.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { printf 'Python 3.10 or newer is required.\n' >&2; exit 69; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || { printf 'Python 3.10 or newer is required.\n' >&2; exit 69; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 -B "$script_dir/interactive_deploy.py" "$@"

