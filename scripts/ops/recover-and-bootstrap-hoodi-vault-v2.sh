#!/usr/bin/env bash
set -euo pipefail
umask 077

# Creates the isolated KV v2 and PKI engines, then installs only the Hoodi
# workload policies/roles. It deliberately does not accept a validator key,
# mnemonic, password, or any custody payload.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { printf 'Usage: %s --validator-set <hoodi-id>\n' "${0##*/}" >&2; exit 64; }
validator_set=''
while [ "$#" -gt 0 ]; do case "$1" in
  --validator-set) validator_set="${2:-}"; shift 2 ;;
  *) usage ;;
esac; done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac

if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then
  exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" --validator-set "$validator_set"
fi
for command in vault jq seq; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

started=false; complete=false; root=''; bootstrap_complete=false
cleanup() {
  local rc=$?
  trap - EXIT
  set +e
  if [ -n "$root" ] && ! VAULT_TOKEN="$root" vault token revoke -self >/dev/null 2>&1; then
    printf '%s\n' 'CRITICAL: generated root token revocation could not be confirmed.' >&2
    rc=70
  fi
  if [ "$started" = true ] && [ "$complete" != true ]; then
    vault operator generate-root -cancel >/dev/null 2>&1 || rc=70
  fi
  unset root VAULT_TOKEN
  if [ "$rc" -eq 0 ] && [ "$bootstrap_complete" = true ]; then
    printf 'PASS: Hoodi Vault v2 runtime boundary is ready for %s; generated root token revoked. Custody onboarding is still required.\n' "$validator_set"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# shellcheck source=scripts/ops/lib/vault-recovery-auth.sh
source "$dir/lib/vault-recovery-auth.sh"
vault_recovery_auth_preflight
status="$(vault operator generate-root -status -format=json)"
[ "$(jq -r .started <<<"$status")" = false ] || { printf '%s\n' 'root-token ceremony already in progress' >&2; exit 75; }
init="$(vault operator generate-root -init -format=json)"; started=true
nonce="$(jq -er .nonce <<<"$init")"; otp="$(jq -er .otp <<<"$init")"; required="$(jq -er .required <<<"$init")"
for number in $(seq 1 "$required"); do
  printf 'Recovery key share %s of %s: ' "$number" "$required" >&2
  IFS= read -r -s share; printf '\n' >&2
  reply="$(printf %s "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share
  if [ "$(jq -r .complete <<<"$reply")" = true ]; then
    complete=true; encoded="$(jq -er .encoded_token <<<"$reply")"; break
  fi
done
[ "$complete" = true ] || { printf '%s\n' 'recovery quorum was not reached' >&2; exit 77; }
root="$(vault_recovery_decode_generated_root "$encoded" "$otp")"; unset encoded otp nonce init reply status
[ -n "$root" ] || { printf '%s\n' 'generated root token is empty' >&2; exit 65; }

VAULT_TOKEN="$root" "$dir/bootstrap-node-operator-vault-v2.sh" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-engine-api-vault.sh" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-validator-runtime-vault.sh" --validator-set "$validator_set" >/dev/null
bootstrap_complete=true
