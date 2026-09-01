#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/test-pr-evidence.sh"
"$script_dir/test-scm-posture.sh"
"$script_dir/test-publish-evidence.sh"
