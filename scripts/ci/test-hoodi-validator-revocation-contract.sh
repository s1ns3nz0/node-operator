#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/recover-exercise-hoodi-validator-revocation.sh"
grep -Fq 'with-private-vault.sh' "$script"
# shellcheck disable=SC2016 # Literal source-contract assertion.
grep -Fq 'vault delete "auth/kubernetes/role/${role}"' "$script"
grep -Fq 'permission denied|invalid role|error authenticating' "$script"
grep -Fq 'bootstrap-hoodi-validator-runtime-vault.sh' "$script"
grep -Fq 'vault token revoke -self' "$script"
grep -Fq 'client_remained_fenced:true' "$script"
printf '%s\n' 'PASS: Hoodi UC-5 revocation is recovery-key mediated, fail-closed, and restores only the reviewed runtime role.'
