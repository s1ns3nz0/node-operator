#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal source-contract fragments
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
library="$root/scripts/ops/lib/vault-recovery-auth.sh"
grep -Fq 'vault_recovery_decode_generated_root' "$library"
grep -Fq 'bytes(a ^ b for a, b in zip(left, right))' "$library"
if rg -n 'generate-root -decode=.*(encoded|otp)' "$root/scripts/ops"; then
  printf '%s\n' 'recovery wrappers must not pass generated-root decode inputs as process arguments' >&2
  exit 1
fi
for script in "$root"/scripts/ops/recover*.sh; do
  if grep -Fq 'operator generate-root -init' "$script" && ! grep -Fq 'vault_recovery_decode_generated_root' "$script"; then
    printf 'recovery wrapper lacks stdin-safe decode: %s\n' "$script" >&2
    exit 1
  fi
done
printf '%s\n' 'PASS: all generated-root recovery wrappers use the shared stdin-safe decoder.'
