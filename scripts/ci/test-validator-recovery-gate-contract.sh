#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/recover-hoodi-validator-signer.sh"
# shellcheck disable=SC2016 # Literal source-contract assertions.
grep -Fq '[ "$client_replicas" = 0 ]' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq '[ "$signer_replicas" = 0 ]' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq '[ -z "$lease_holder" ]' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertions.
grep -Fq 'data-validator-${validator_set}-slashing-db-0' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq 'validator-${validator_set}-remote-signer' "$script"
if grep -Eq 'kubectl .*delete|scale deployment hoodi-validator-client --replicas=1' "$script"; then printf '%s\n' 'recovery may delete data or activate validator client' >&2; exit 1; fi
printf '%s\n' 'PASS: recovery preserves slashing history and keeps validator client fenced.'
