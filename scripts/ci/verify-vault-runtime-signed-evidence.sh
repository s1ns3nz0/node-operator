#!/usr/bin/env bash
# Check objective: Verify signed Vault runtime evidence has trusted identity and required semantics.
# Consumer entrypoint: require both cryptographic identity and evidence semantics.
set -euo pipefail
test "$#" = 4 || { echo 'usage: verify-vault-runtime-signed-evidence.sh EVIDENCE_ROOT TRUSTED_REVISION RUN_ID RUN_ATTEMPT' >&2; exit 64; }
evidence="$1"; revision="$2"; run_id="$3"; attempt="$4"
[[ "$revision" =~ ^[a-f0-9]{40}$ && "$run_id" =~ ^[1-9][0-9]*$ && "$attempt" =~ ^[1-9][0-9]*$ ]] || exit 64
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
statement="$evidence/verification-statement.json"
bundle="$evidence/verification-statement.sigstore.json"
test -d "$evidence" && test ! -L "$evidence"
test -s "$statement" && test ! -L "$statement"
test -s "$bundle" && test ! -L "$bundle"
# Never accept a caller-provided key/identity, regex identity, or skip SCT/tlog.
cosign verify-blob --bundle "$bundle" \
  --certificate-identity 'https://github.com/s1ns3nz0/node-operator/.github/workflows/vault-runtime-candidate-verification.yml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --certificate-github-workflow-sha "$revision" \
  --certificate-github-workflow-repository 's1ns3nz0/node-operator' \
  --certificate-github-workflow-ref 'refs/heads/main' \
  --certificate-github-workflow-trigger workflow_dispatch \
  "$statement"
python3 "$root/scripts/ci/vault-runtime-verification-statement.py" verify "$evidence" "$revision" "$run_id" "$attempt" "$statement"
printf 'PASS: exact identity signature and fresh digest-bound verification evidence. Not build provenance or deployment authorization.\n'
