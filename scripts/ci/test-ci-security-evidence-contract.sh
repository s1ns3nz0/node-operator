#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workflow="$script_dir/../../.github/workflows/ci-security.yml"

# The scanner produces the sole uploadable evidence under runner.temp, rather
# than a hidden checkout path. This preserves upload-artifact's safe default
# (hidden files excluded) and prevents an accidental workspace-wide upload.
grep -Fq 'EVIDENCE_ROOT: ${{ runner.temp }}/security-evidence' "$workflow"
grep -Fq 'path: ${{ env.EVIDENCE_ROOT }}' "$workflow"
if grep -Fq 'include-hidden-files: true' "$workflow"; then
  printf 'security evidence upload must not include hidden files\n' >&2
  exit 1
fi

printf 'PASS: scanner evidence is confined to a non-hidden runner-temp directory.\n'
