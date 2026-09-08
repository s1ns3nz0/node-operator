#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/start-hoodi-validator-signer.sh"
grep -Fq 'with-private-eks.sh' "$script"
grep -Fq 'PRIVATE_EKS_SESSION' "$script"
grep -Fq 'op:"test"' "$script"
grep -Fq '/spec/holderIdentity' "$script"
grep -Fq 'date -u +%Y-%m-%dT%H:%M:%S.000000Z' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertions.
grep -Fq 'scale deployment "$signer" --replicas=1' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq '[ "$replicas" = 0 ]' "$script"
printf '%s\n' 'PASS: signer start atomically claims an empty set-specific fence lease.'
