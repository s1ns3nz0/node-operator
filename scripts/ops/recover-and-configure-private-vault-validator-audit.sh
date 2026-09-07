#!/usr/bin/env bash
set -euo pipefail

# Configures the two non-raw Vault validator-audit devices through a recovery
# quorum. The generated root token is process-local and revoked on every exit.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then
  exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0"
fi
for command in vault jq kubectl; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

started=false; complete=false; root_token=''
cleanup() {
  set +e
  [ -n "$root_token" ] && VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1 || true
  [ "$started" = true ] && [ "$complete" != true ] && vault operator generate-root -cancel >/dev/null 2>&1 || true
  unset VAULT_TOKEN root_token
}
trap cleanup EXIT INT TERM

statefulset="$(kubectl -n vault get statefulset vault -o json)"
jq -e 'all(.spec.template.spec.containers[]; select(.name == "vault-validator-audit-relay") | .securityContext.readOnlyRootFilesystem == true) and any(.spec.template.spec.containers[]; .name == "vault-validator-audit-relay")' <<<"$statefulset" >/dev/null || {
  printf '%s\n' 'Vault audit relay is absent or unsafe; refusing audit-device ceremony.' >&2; exit 65;
}
for pod in vault-0 vault-1 vault-2; do
  kubectl -n vault get pod "$pod" -o json | jq -e '[.status.containerStatuses[] | select(.name == "vault-validator-audit-relay") | .ready] == [true]' >/dev/null || {
    printf 'Vault audit relay is not ready: %s\n' "$pod" >&2; exit 65;
  }
  kubectl -n vault exec "$pod" -c vault-validator-audit-relay -- test -S /vault/audit/validator-audit.sock || {
    printf 'Vault audit socket is not bound: %s\n' "$pod" >&2; exit 65;
  }
done

status="$(vault operator generate-root -status -format=json)"
[ "$(jq -r '.started' <<<"$status")" = false ] || { printf '%s\n' 'a root-token generation ceremony is already in progress' >&2; exit 75; }
init="$(vault operator generate-root -init -format=json)"; started=true
nonce="$(jq -er '.nonce' <<<"$init")"; otp="$(jq -er '.otp' <<<"$init")"; required="$(jq -er '.required' <<<"$init")"
for number in $(seq 1 "$required"); do
  printf 'Recovery key share %s of %s: ' "$number" "$required" >&2
  IFS= read -r -s share; printf '\n' >&2
  submitted="$(printf '%s' "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share
  if [ "$(jq -r '.complete' <<<"$submitted")" = true ]; then complete=true; encoded="$(jq -er '.encoded_token' <<<"$submitted")"; break; fi
done
[ "$complete" = true ] || { printf '%s\n' 'recovery quorum was not reached' >&2; exit 77; }
root_token="$(vault operator generate-root -decode="$encoded" -otp="$otp")"
unset encoded otp nonce init submitted status

devices="$(VAULT_TOKEN="$root_token" vault audit list -format=json)"
if ! jq -e 'has("validator-file/")' <<<"$devices" >/dev/null; then
  VAULT_TOKEN="$root_token" vault audit enable -path=validator-file file file_path=/vault/audit/validator-audit.json log_raw=false hmac_accessor=false elide_list_responses=true
fi
if ! jq -e 'has("validator-socket/")' <<<"$devices" >/dev/null; then
  VAULT_TOKEN="$root_token" vault audit enable -path=validator-socket socket address=unix:///vault/audit/validator-audit.sock log_raw=false hmac_accessor=false elide_list_responses=true
fi
VAULT_TOKEN="$root_token" "$dir/verify-vault-validator-audit.sh"
printf '%s\n' 'PASS: Vault validator file/socket audit devices were configured and the generated root token will now be revoked.'
