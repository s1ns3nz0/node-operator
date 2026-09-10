#!/usr/bin/env bash
# Prepare TLS records for an existing validator without changing live policies,
# workloads, or the public known-clients ConfigMap.
set +x
set -euo pipefail
umask 077
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() { printf 'Usage: %s --validator-set <hoodi-id> --output-dir <new-absolute-dir>\n' "${0##*/}" >&2; exit 64; }
validator_set=''; output=''; verify_only=false
while [ "$#" -gt 0 ]; do case "$1" in
  --validator-set) validator_set="${2:-}"; shift 2 ;;
  --output-dir) output="${2:-}"; shift 2 ;;
  --verify-only) verify_only=true; shift ;;
  *) usage ;;
esac; done
[[ "$validator_set" =~ ^hoodi-[a-z0-9][a-z0-9-]{0,35}$ ]] || usage
[[ "$output" = /* ]] && [ ! -e "$output" ] && [ ! -L "$output" ] || usage
: "${VAULT_TOKEN:?A short-lived administrator token is required}"
for command in vault jq openssl base64 mktemp; do command -v "$command" >/dev/null || exit 69; done
if ! openssl version | grep -q '^OpenSSL 3\.'; then
  if [ -x /opt/homebrew/opt/openssl@3/bin/openssl ]; then
    PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
  elif [ -x /usr/local/opt/openssl@3/bin/openssl ]; then
    PATH="/usr/local/opt/openssl@3/bin:$PATH"
  fi
fi
openssl version | grep -q '^OpenSSL 3\.' || {
  printf '%s\n' 'OpenSSL 3 is required; install openssl@3 before starting this ceremony.' >&2
  exit 69
}
scratch="$(mktemp -d /private/tmp/node-operator-v2-transport.XXXXXX)"
cleanup() {
  local rc=$?
  trap - EXIT
  find "$scratch" -type f -exec unlink {} \;
  rmdir "$scratch"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if [ "$verify_only" = false ]; then "$dir/bootstrap-node-operator-vault-v2.sh" >/dev/null; fi
base="node-operator-runtime/data/validators/hoodi/$validator_set/runtime"
server="validator-$validator_set-remote-signer.validator-operations.svc"
client="validator-$validator_set-client.validator-operations.svc"

for identity in signer client; do
  destination="$base/$identity-tls"
  if vault read -format=json "$destination" > "$scratch/record" 2>/dev/null; then
    jq -e '.data.data | select(type == "object")' "$scratch/record" > "$scratch/$identity.json"
    continue
  fi
  [ "$verify_only" = false ] || { printf '%s\n' 'required transport record is unavailable; refusing authorization cutover' >&2; exit 65; }
  common_name="$client"; [ "$identity" != signer ] || common_name="$server"
  vault write -format=json node-operator-pki/issue/validator-mtls common_name="$common_name" alt_names="$common_name.cluster.local" ttl=720h > "$scratch/issued"
  jq -er '.data.private_key' "$scratch/issued" > "$scratch/key"
  jq -er '.data.certificate' "$scratch/issued" > "$scratch/cert"
  jq -er '.data.issuing_ca' "$scratch/issued" > "$scratch/ca"
  if [ "$identity" = signer ]; then
    openssl rand -hex 32 > "$scratch/password"
    openssl pkcs12 -export -inkey "$scratch/key" -in "$scratch/cert" -certfile "$scratch/ca" -out "$scratch/server.p12" -passout "file:$scratch/password" >/dev/null 2>&1
    base64 < "$scratch/server.p12" | tr -d '\n' > "$scratch/p12-b64"
    jq -n --rawfile p12 "$scratch/p12-b64" --rawfile password "$scratch/password" '{pkcs12_b64:$p12,password:($password | rtrimstr("\n"))}' > "$scratch/$identity.json"
  else
    base64 < "$scratch/cert" | tr -d '\n' > "$scratch/cert-b64"
    base64 < "$scratch/key" | tr -d '\n' > "$scratch/key-b64"
    base64 < "$scratch/ca" | tr -d '\n' > "$scratch/ca-b64"
    jq -n --rawfile cert "$scratch/cert-b64" --rawfile key "$scratch/key-b64" --rawfile ca "$scratch/ca-b64" '{tls_crt_b64:$cert,tls_key_b64:$key,ca_crt_b64:$ca}' > "$scratch/$identity.json"
  fi
  jq '{options:{cas:0},data:.}' "$scratch/$identity.json" > "$scratch/payload"
  vault write "$destination" @"$scratch/payload" >/dev/null
  vault read -format=json "$destination" > "$scratch/record"
  jq -e --slurpfile expected "$scratch/$identity.json" '.data.data == $expected[0]' "$scratch/record" >/dev/null
done

# Validate stored bytes, including retries, before publishing public outputs.
jq -er '.pkcs12_b64' "$scratch/signer.json" | openssl base64 -d -A > "$scratch/server.p12"
jq -er '.password' "$scratch/signer.json" > "$scratch/password"
openssl pkcs12 -in "$scratch/server.p12" -passin "file:$scratch/password" -clcerts -nokeys -out "$scratch/server.crt" >/dev/null 2>&1
openssl pkcs12 -in "$scratch/server.p12" -passin "file:$scratch/password" -nocerts -noenc -out "$scratch/server.key" >/dev/null 2>&1
jq -er '.tls_crt_b64' "$scratch/client.json" | openssl base64 -d -A > "$scratch/client.crt"
jq -er '.tls_key_b64' "$scratch/client.json" | openssl base64 -d -A > "$scratch/client.key"
jq -er '.ca_crt_b64' "$scratch/client.json" | openssl base64 -d -A > "$scratch/ca.crt"
openssl verify -CAfile "$scratch/ca.crt" -purpose sslserver -verify_hostname "$server" "$scratch/server.crt" >/dev/null
openssl verify -CAfile "$scratch/ca.crt" -purpose sslclient "$scratch/client.crt" >/dev/null
for identity in server client; do openssl x509 -in "$scratch/$identity.crt" -checkend 86400 -noout >/dev/null; done
for identity in server client; do
  openssl x509 -in "$scratch/$identity.crt" -pubkey -noout > "$scratch/cert-public"
  openssl pkey -in "$scratch/$identity.key" -pubout > "$scratch/key-public"
  cmp "$scratch/cert-public" "$scratch/key-public" >/dev/null
done
fingerprint="$(openssl x509 -in "$scratch/client.crt" -noout -fingerprint -sha256)"
fingerprint="${fingerprint#*=}"
mkdir -m 700 "$output"
install -m 644 "$scratch/ca.crt" "$output/signer-ca.crt"
printf 'validator-%s-client %s\n' "$validator_set" "$fingerprint" > "$output/known-clients.txt"
printf '%s\n' 'PASS: Vault PKI transport records prepared and verified; public trust outputs written. Live workloads and policies unchanged.'
