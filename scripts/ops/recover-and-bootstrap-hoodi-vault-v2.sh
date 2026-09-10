#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

# Creates the isolated KV v2 and PKI engines, then installs only the Hoodi
# workload policies/roles. It deliberately does not accept a validator key,
# mnemonic, password, or any custody payload.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { printf 'Usage: %s --validator-set <hoodi-id> [--prepare-existing --output-dir <new-absolute-dir>]\n' "${0##*/}" >&2; exit 64; }
validator_set=''; prepare_existing=false; output=''
while [ "$#" -gt 0 ]; do case "$1" in
  --validator-set) validator_set="${2:-}"; shift 2 ;;
  --prepare-existing) prepare_existing=true; shift ;;
  --output-dir) output="${2:-}"; shift 2 ;;
  *) usage ;;
esac; done
[[ "$validator_set" =~ ^hoodi-[a-z0-9][a-z0-9-]{0,35}$ ]] || usage
args=(--validator-set "$validator_set")
if [ "$prepare_existing" = true ]; then
  [[ "$output" = /* ]] && [ ! -e "$output" ] && [ ! -L "$output" ] || usage
  args+=(--prepare-existing --output-dir "$output")
elif [ -n "$output" ]; then usage; fi

if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then
  exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" "${args[@]}"
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
    if [ "$prepare_existing" = true ]; then
      if ! jq -n --arg set "$validator_set" --arg now "$(date -u +%FT%TZ)" \
        '{schema_version:1,operation:"prepare-existing-hoodi-vault-v2",validator_set:$set,
          collected_at_utc:$now,runtime_mount:"node-operator-runtime",custody_preserved:true,
          transport_verified:true,engine_jwt_verified:true,generated_root_revoked:true,
          live_policies_changed:false,live_workloads_changed:false,secret_values_emitted:false}' \
        > "$output/preparation.json"; then exit 74; fi
      printf 'PASS: existing custody and Vault v2 transport/JWT prepared for %s; generated root token revoked. Live cutover remains required.\n' "$validator_set"
    else
    printf 'PASS: Hoodi Vault v2 runtime boundary is ready for %s; generated root token revoked. Custody onboarding is still required.\n' "$validator_set"
    fi
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

if [ "$prepare_existing" = true ]; then
VAULT_TOKEN="$root" "$dir/copy-hoodi-custody-to-runtime-v2.sh" --validator-set "$validator_set" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-engine-api-vault.sh" --prepare-only >/dev/null
VAULT_TOKEN="$root" "$dir/prepare-hoodi-vault-v2-transport.sh" --validator-set "$validator_set" --output-dir "$output" >/dev/null
else
VAULT_TOKEN="$root" "$dir/bootstrap-node-operator-vault-v2.sh" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-engine-api-vault.sh" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-validator-runtime-vault.sh" --validator-set "$validator_set" >/dev/null
fi
bootstrap_complete=true
