#!/usr/bin/env bash
# shellcheck disable=SC2016 # literal source-contract fragments
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/apply-live-validator-vault-cutover.sh"
test -x "$script"; bash -n "$script"
for required in \
  'signing-proxy-fence' \
  'client_and_fence_quiesced == true' \
  'direct_client_to_signer_denied == true' \
  'dry-run=server' \
  'Vault signer TLS injection' \
  'Vault client TLS injection' \
  'scale deployment "$signer" --replicas=1' \
  'signing_fence_replicas:0' \
  'activation_required:true' \
  'validator client must remain at zero' \
  'legacy_tls_secrets_retained:true'; do grep -Fq "$required" "$script" || { printf 'missing validator cutover control: %s\n' "$required" >&2; exit 1; }; done
if grep -Eq 'delete secret.*(signer|client)-tls|create secret generic' "$script"; then printf '%s\n' 'validator cutover must retain legacy TLS Secrets and never create replacements' >&2; exit 1; fi
if grep -Fq 'scale deployment "$fence_deployment" --replicas=1' "$script"; then
  printf '%s\n' 'staging must not start the identity-bound fence without its client' >&2; exit 1
fi
printf '%s\n' 'PASS: validator cutover restores signer only; client and fence stay zero until activation.'
