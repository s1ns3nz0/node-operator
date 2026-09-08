#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
collector="$root/scripts/ops/collect-hoodi-validator-evidence.sh"

bash -n "$collector"
grep -Fq "tr '[:lower:]' '[:upper:]'" "$collector"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq 'lease "validator-${validator_set}-primary"' "$collector"
if grep -Fq 'phase^^' "$collector"; then
  printf '%s\n' 'collector requires a Bash 4-only uppercase expansion' >&2
  exit 1
fi
printf '%s\n' 'PASS: lifecycle evidence collector remains compatible with the macOS Bash runtime.'
