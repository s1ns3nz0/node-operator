#!/usr/bin/env bash
# Check objective: Enforce the pinned OpenSSF Scorecard workflow and bounded evidence output.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
workflow="$root/.github/workflows/repository-posture.yml"
script="$root/scripts/ci/normalize-scorecard-evidence.sh"
grep -Fq 'ossf/scorecard-action@2d1146689b8cda280b9bc96326124645441f03bc' "$workflow"
grep -Fq 'github/codeql-action/upload-sarif@a65a038433a26f4363cf9f029e3b9ceac831ad5d' "$workflow"
grep -Fq 'publish_results: true' "$workflow"
grep -Fq 'security-events: write' "$workflow"
grep -Fq 'id-token: write' "$workflow"
grep -Fq 'retention-days: 90' "$workflow"
grep -Fq 'Scorecard SARIF schema is invalid' "$script"
printf '%s\n' 'PASS: repository posture and Scorecard evidence contracts are pinned and bounded.'
