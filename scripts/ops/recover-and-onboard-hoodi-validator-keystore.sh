#!/usr/bin/env bash
set -euo pipefail
# Recovery-key, one-time custody ceremony. No secret is printed or retained.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage(){ printf 'Usage: %s --validator-set <hoodi-id> --keystore-dir <absolute-dir> --signer-ca-output <absolute-pem> --known-clients-output <absolute-file> [--refresh-auth-only]\n' "${0##*/}" >&2; exit 64; }
set_id=''; key_dir=''; ca_out=''; known_out=''; refresh_auth_only=false
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) set_id="${2:-}"; shift 2;; --keystore-dir) key_dir="${2:-}"; shift 2;; --signer-ca-output) ca_out="${2:-}"; shift 2;; --known-clients-output) known_out="${2:-}"; shift 2;; --refresh-auth-only) refresh_auth_only=true; shift;; *) usage;; esac; done
case "$set_id" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage;; esac; case "$key_dir:$ca_out:$known_out" in /*:/*:/*) ;; *) usage;; esac
if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" --validator-set "$set_id" --keystore-dir "$key_dir" --signer-ca-output "$ca_out" --known-clients-output "$known_out"; fi
for x in vault jq openssl base64 find kubectl mktemp; do command -v "$x" >/dev/null || { printf 'missing command: %s\n' "$x" >&2; exit 69; }; done
keys=(); while IFS= read -r key; do keys+=("$key"); done < <(find "$key_dir" -maxdepth 1 -type f -name 'keystore-*.json' -print); [ "${#keys[@]}" = 1 ] || { printf 'expected exactly one keystore JSON\n' >&2; exit 64; }
tmp="$(mktemp -d /private/tmp/node-operator-hoodi-onboard.XXXXXX)"; chmod 700 "$tmp"
started=false; complete=false; root=''; child=''
cleanup(){ set +e; [ -z "$child" ] || VAULT_TOKEN="$root" vault token revoke "$child" >/dev/null 2>&1; [ -z "$root" ] || VAULT_TOKEN="$root" vault token revoke -self >/dev/null 2>&1; [ "$started" = true ] && [ "$complete" != true ] && vault operator generate-root -cancel >/dev/null 2>&1; find "$tmp" -type f -exec unlink {} \; 2>/dev/null; rmdir "$tmp" 2>/dev/null; unset root child VAULT_TOKEN; }
trap cleanup EXIT INT TERM
# shellcheck source=scripts/ops/lib/vault-recovery-auth.sh
source "$dir/lib/vault-recovery-auth.sh"
vault_recovery_auth_preflight
status="$(vault operator generate-root -status -format=json)"
if [ "$(jq -r .started <<<"$status")" = true ]; then
  progress="$(jq -er '.progress // 0' <<<"$status")"
  required_existing="$(jq -er '.required // 0' <<<"$status")"
  printf '\n╭────────────────────────────────────────────────────────────╮\n' >&2
  printf '│ 🔁 EXISTING ROOT-TOKEN CEREMONY DETECTED                  │\n' >&2
  printf '╰────────────────────────────────────────────────────────────╯\n' >&2
  printf '%s\n' 'This is not Vault first-run initialization; a previous generate-root ceremony is pending.' >&2
  printf 'Current progress: %s/%s recovery shares.\n' "$progress" "$required_existing" >&2
  printf '%s\n' 'Type CANCEL to discard it and start a new interactive ceremony, or EXIT to leave it untouched.' >&2
  printf 'Action [CANCEL/EXIT]: ' >&2
  IFS= read -r ceremony_action
  case "$ceremony_action" in
    CANCEL)
      vault operator generate-root -cancel >/dev/null
      status="$(vault operator generate-root -status -format=json)"
      [ "$(jq -r .started <<<"$status")" = false ] || { printf '%s\n' 'existing root-token ceremony could not be cancelled' >&2; exit 75; }
      printf '%s\n' 'Existing root-token ceremony cancelled by operator request.' >&2
      ;;
    EXIT|'')
      printf '%s\n' 'Leaving the existing root-token ceremony untouched.' >&2
      exit 0
      ;;
    *)
      printf '%s\n' 'Invalid action; leaving the existing root-token ceremony untouched.' >&2
      exit 64
      ;;
  esac
fi
printf '\n╭────────────────────────────────────────────────────────────╮\n' >&2
printf '│ 🔐 VAULT ADMIN RECOVERY CEREMONY                          │\n' >&2
printf '╰────────────────────────────────────────────────────────────╯\n' >&2
printf '%s\n' 'This ceremony creates a temporary administrator token from recovery shares.' >&2
printf '%s\n' 'It does not initialize Vault and does not produce unseal keys.' >&2
printf '%s\n' 'Each share is requested once and never echoed.' >&2
init="$(vault operator generate-root -init -format=json)"; started=true; nonce="$(jq -er .nonce <<<"$init")"; otp="$(jq -er .otp <<<"$init")"; required="$(jq -er .required <<<"$init")"
printf 'Recovery policy: %s shares required for this ceremony.\n' "$required" >&2
for n in $(seq 1 "$required"); do printf 'Recovery key share %s of %s: ' "$n" "$required" >&2; IFS= read -r -s share; printf '\n' >&2; reply="$(printf %s "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share; if [ "$(jq -r .complete <<<"$reply")" = true ]; then complete=true; encoded="$(jq -er .encoded_token <<<"$reply")"; break; fi; done
[ "$complete" = true ] || { printf 'recovery quorum was not reached\n' >&2; exit 77; }
root="$(vault_recovery_decode_generated_root "$encoded" "$otp")"; unset encoded otp nonce init reply status
[ -n "$root" ] || { printf '%s\n' 'generated root token is empty' >&2; exit 65; }

# Refresh Kubernetes Auth with the Vault server's service-account reviewer
# rather than persisting a short-lived local TokenRequest JWT.
cluster_ca="$tmp/cluster-ca.crt"
cluster_ca_b64="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
[ -n "$cluster_ca_b64" ] || { printf '%s\n' 'Kubernetes cluster CA is unavailable' >&2; exit 65; }
if ! printf '%s' "$cluster_ca_b64" | base64 -D > "$cluster_ca" 2>/dev/null; then
  printf '%s' "$cluster_ca_b64" | base64 --decode > "$cluster_ca"
fi
VAULT_TOKEN="$root" vault auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null 2>&1 ||
  VAULT_TOKEN="$root" vault auth enable kubernetes >/dev/null
VAULT_TOKEN="$root" vault write auth/kubernetes/config \
  kubernetes_host=https://kubernetes.default.svc:443 \
  kubernetes_ca_cert="@$cluster_ca" \
  disable_local_ca_jwt=false >/dev/null
printf '%s\n' 'PASS: Kubernetes Auth reviewer configuration refreshed without persisting an expiring reviewer token.' >&2
if [ "$refresh_auth_only" = true ]; then
  printf '%s\n' 'PASS: Kubernetes Auth refresh-only ceremony completed; no custody records were changed.' >&2
  exit 0
fi
base="node-operator-runtime/validators/hoodi/$set_id/runtime"
had_signer_tls=false; had_client_tls=false
VAULT_TOKEN="$root" vault kv metadata get "$base/signer-tls" >/dev/null 2>&1 && had_signer_tls=true
VAULT_TOKEN="$root" vault kv metadata get "$base/client-tls" >/dev/null 2>&1 && had_client_tls=true
existing_records=true
for record in keystore password slashing-db-password signer-tls client-tls; do
  if ! VAULT_TOKEN="$root" vault kv metadata get "$base/$record" >/dev/null 2>&1; then
    existing_records=false
    break
  fi
done
if [ "$existing_records" = true ]; then
  printf '%s\n' 'PASS: existing custody records detected; preserving them and skipping overwrite.' >&2
  exit 0
fi
VAULT_TOKEN="$root" "$dir/bootstrap-node-operator-vault-v2.sh" >/dev/null
VAULT_TOKEN="$root" "$dir/bootstrap-hoodi-validator-runtime-vault.sh" --validator-set "$set_id" >/dev/null
child="$(VAULT_TOKEN="$root" vault token create -orphan -no-default-policy -policy="hoodi-$set_id-onboarding" -ttl=10m -field=token)"
printf 'Keystore password: ' >&2; IFS= read -r -s key_password; printf '\n' >&2
[ -n "$key_password" ] || { printf 'empty keystore password is not allowed\n' >&2; exit 64; }
tls_password="$(openssl rand -base64 48 | tr -d '\n')"; service="validator-$set_id-remote-signer"
server_issue="$(VAULT_TOKEN="$root" vault write -format=json node-operator-pki/issue/validator-mtls common_name="$service.validator-operations.svc" alt_names="$service.validator-operations.svc,$service.validator-operations.svc.cluster.local" ttl=720h)"
client_issue="$(VAULT_TOKEN="$root" vault write -format=json node-operator-pki/issue/validator-mtls common_name="validator-$set_id-client.validator-operations.svc" ttl=720h)"
jq -er '.data.private_key' <<<"$server_issue" > "$tmp/tls.key"
jq -er '.data.certificate' <<<"$server_issue" > "$tmp/server.crt"
jq -er '(.data.ca_chain[0] // .data.issuing_ca)' <<<"$server_issue" > "$tmp/ca.crt"
jq -er '.data.private_key' <<<"$client_issue" > "$tmp/client.key"
jq -er '.data.certificate' <<<"$client_issue" > "$tmp/client.crt"
unset server_issue client_issue
openssl pkcs12 -export -out "$tmp/tls.p12" -inkey "$tmp/tls.key" -in "$tmp/server.crt" -certfile "$tmp/ca.crt" -passout "pass:$tls_password" >/dev/null 2>&1

# KV v2 CAS=0 is create-only.  A previous interrupted ceremony may have
# written only some records, so treat each record independently: preserve an
# existing value and create only missing records.  If another operator wins
# the race between the metadata read and the write, re-check and accept it.
put_if_absent() {
  local path="$1" mode="$2" value_file="$3" key_name="${4:-password}"
  if VAULT_TOKEN="$root" vault kv metadata get "$path" >/dev/null 2>&1; then
    return 0
  fi
  if [ "$mode" = stdin ]; then
    if ! VAULT_TOKEN="$child" vault kv put -cas=0 "$path" "$key_name"=- < "$value_file" >/dev/null 2>&1; then
      VAULT_TOKEN="$root" vault kv metadata get "$path" >/dev/null 2>&1 || return 1
    fi
  else
    if ! VAULT_TOKEN="$child" vault kv put -cas=0 "$path" @"$value_file" >/dev/null 2>&1; then
      VAULT_TOKEN="$root" vault kv metadata get "$path" >/dev/null 2>&1 || return 1
    fi
  fi
}

put_if_absent "$base/keystore" stdin "${keys[0]}" keystore
printf %s "$key_password" > "$tmp/keystore-password"
put_if_absent "$base/password" stdin "$tmp/keystore-password"
openssl rand -base64 48 | tr -d '\n' > "$tmp/slashing-db-password"
put_if_absent "$base/slashing-db-password" stdin "$tmp/slashing-db-password"
{ printf '{"pkcs12_b64":"'; base64 < "$tmp/tls.p12" | tr -d '\n'; printf '","password":"%s"}\n' "$tls_password"; } > "$tmp/tls.json"
put_if_absent "$base/signer-tls" json "$tmp/tls.json"
{ printf '{"tls_crt_b64":"'; base64 < "$tmp/client.crt" | tr -d '\n'; printf '","tls_key_b64":"'; base64 < "$tmp/client.key" | tr -d '\n'; printf '","ca_crt_b64":"'; base64 < "$tmp/ca.crt" | tr -d '\n'; printf '"}\n'; } > "$tmp/client-tls.json"
put_if_absent "$base/client-tls" json "$tmp/client-tls.json"
fingerprint="$(openssl x509 -in "$tmp/client.crt" -noout -fingerprint -sha256)"; fingerprint="${fingerprint#*=}"
install -d -m 700 "$(dirname "$ca_out")" "$(dirname "$known_out")"
# Do not replace public material that corresponds to a preserved Vault record
# with the newly generated (and discarded) certificate from this retry.
if [ "$had_signer_tls" = false ] || [ ! -s "$ca_out" ]; then
  install -m 644 "$tmp/ca.crt" "$ca_out"
fi
if [ "$had_client_tls" = false ] || [ ! -s "$known_out" ]; then
  printf 'validator-%s-client.validator-operations.svc %s\n' "$set_id" "$fingerprint" > "$known_out"
fi
chmod 644 "$known_out"
unset key_password tls_password
printf 'PASS: Hoodi custody records and signer TLS were created for %s; public CA saved to %s.\n' "$set_id" "$ca_out"
