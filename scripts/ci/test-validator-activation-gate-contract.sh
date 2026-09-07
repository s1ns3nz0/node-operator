#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/activate-hoodi-validator-client.sh"
grep -Fq -- '--confirm-public-key' "$script"
grep -Fq -- '--confirm-withdrawal-address' "$script"
grep -Fq '.payload.validator.status == "active_ongoing"' "$script"
grep -Fq '.payload.syncing.is_syncing == false' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq '[ "$replicas" = 0 ]' "$script"
grep -Fq 'kubectl -n validator-operations scale deployment' "$script"
printf '%s\n' 'PASS: validator activation requires independent public confirmations and active private Beacon evidence.'
