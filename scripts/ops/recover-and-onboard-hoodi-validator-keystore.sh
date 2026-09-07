#!/usr/bin/env bash
set -euo pipefail
# Recovery-key, one-time custody ceremony. No secret is printed or retained.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage(){ printf 'Usage: %s --validator-set <hoodi-id> --keystore-dir <absolute-dir> --signer-ca-output <absolute-pem>\n' "${0##*/}" >&2; exit 64; }
set_id=''; key_dir=''; ca_out=''
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) set_id="${2:-}"; shift 2;; --keystore-dir) key_dir="${2:-}"; shift 2;; --signer-ca-output) ca_out="${2:-}"; shift 2;; *) usage;; esac; done
case "$set_id" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage;; esac; case "$key_dir:$ca_out" in /*:/*) ;; *) usage;; esac
if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" --validator-set "$set_id" --keystore-dir "$key_dir" --signer-ca-output "$ca_out"; fi
for x in vault jq openssl base64 find; do command -v "$x" >/dev/null || { printf 'missing command: %s\n' "$x" >&2; exit 69; }; done
keys=(); while IFS= read -r key; do keys+=("$key"); done < <(find "$key_dir" -maxdepth 1 -type f -name 'keystore-*.json' -print); [ "${#keys[@]}" = 1 ] || { printf 'expected exactly one keystore JSON\n' >&2; exit 64; }
tmp="$(mktemp -d /private/tmp/node-operator-hoodi-onboard.XXXXXX)"; chmod 700 "$tmp"
started=false; complete=false; root=''; child=''
cleanup(){ set +e; [ -z "$child" ] || VAULT_TOKEN="$root" vault token revoke "$child" >/dev/null 2>&1; [ -z "$root" ] || VAULT_TOKEN="$root" vault token revoke -self >/dev/null 2>&1; [ "$started" = true ] && [ "$complete" != true ] && vault operator generate-root -cancel >/dev/null 2>&1; find "$tmp" -type f -exec unlink {} \; 2>/dev/null; rmdir "$tmp" 2>/dev/null; unset root child VAULT_TOKEN; }
trap cleanup EXIT INT TERM
status="$(vault operator generate-root -status -format=json)"; [ "$(jq -r .started <<<"$status")" = false ] || { printf 'root-token ceremony already in progress\n' >&2; exit 75; }
init="$(vault operator generate-root -init -format=json)"; started=true; nonce="$(jq -er .nonce <<<"$init")"; otp="$(jq -er .otp <<<"$init")"; required="$(jq -er .required <<<"$init")"
for n in $(seq 1 "$required"); do printf 'Recovery key share %s of %s: ' "$n" "$required" >&2; IFS= read -r -s share; printf '\n' >&2; reply="$(printf %s "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share; if [ "$(jq -r .complete <<<"$reply")" = true ]; then complete=true; encoded="$(jq -er .encoded_token <<<"$reply")"; break; fi; done
[ "$complete" = true ] || { printf 'recovery quorum was not reached\n' >&2; exit 77; }
root="$(vault operator generate-root -decode="$encoded" -otp="$otp")"; unset encoded otp nonce init reply status
child="$(VAULT_TOKEN="$root" vault token create -orphan -no-default-policy -policy="hoodi-$set_id-onboarding" -ttl=10m -field=token)"
printf 'Keystore password: ' >&2; IFS= read -r -s key_password; printf '\n' >&2
[ -n "$key_password" ] || { printf 'empty keystore password is not allowed\n' >&2; exit 64; }
tls_password="$(openssl rand -base64 48 | tr -d '\n')"
openssl req -x509 -newkey rsa:3072 -nodes -days 30 -subj "/CN=validator-$set_id-remote-signer" -keyout "$tmp/tls.key" -out "$tmp/ca.crt" >/dev/null 2>&1
openssl pkcs12 -export -out "$tmp/tls.p12" -inkey "$tmp/tls.key" -in "$tmp/ca.crt" -passout "pass:$tls_password" >/dev/null 2>&1
base="kv/validators/hoodi/$set_id/runtime"
VAULT_TOKEN="$child" vault kv put -cas=0 "$base/keystore" keystore=- < "${keys[0]}" >/dev/null
printf %s "$key_password" | VAULT_TOKEN="$child" vault kv put -cas=0 "$base/password" password=- >/dev/null
openssl rand -base64 48 | tr -d '\n' | VAULT_TOKEN="$child" vault kv put -cas=0 "$base/slashing-db-password" password=- >/dev/null
{ printf '{"pkcs12_b64":"'; base64 < "$tmp/tls.p12" | tr -d '\n'; printf '","password":"%s"}\n' "$tls_password"; } > "$tmp/tls.json"
VAULT_TOKEN="$child" vault kv put -cas=0 "$base/signer-tls" @"$tmp/tls.json" >/dev/null
install -d -m 700 "$(dirname "$ca_out")"; install -m 644 "$tmp/ca.crt" "$ca_out"
unset key_password tls_password
printf 'PASS: Hoodi custody records and signer TLS were created for %s; public CA saved to %s.\n' "$set_id" "$ca_out"
