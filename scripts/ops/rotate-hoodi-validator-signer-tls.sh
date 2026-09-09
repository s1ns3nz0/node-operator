#!/usr/bin/env bash
set -euo pipefail

# Rotates only the public-serving Web3Signer TLS record. It never reads or
# rewrites the BLS keystore, its password, or the slashing database credential.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage() {
  printf 'Usage: %s --validator-set <hoodi-id> --current-ca <absolute-pem> --previous-ca-output <absolute-pem> --new-ca-output <absolute-pem>\n' "${0##*/}" >&2
  exit 64
}
validator_set=''; current_ca=''; previous_ca_output=''; new_ca_output=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --current-ca) current_ca="${2:-}"; shift 2 ;;
    --previous-ca-output) previous_ca_output="${2:-}"; shift 2 ;;
    --new-ca-output) new_ca_output="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$current_ca:$previous_ca_output:$new_ca_output" in /*:/*:/*) ;; *) usage ;; esac
[ "$current_ca" != "$previous_ca_output" ] && [ "$current_ca" != "$new_ca_output" ] && [ "$previous_ca_output" != "$new_ca_output" ] || usage

if [ "${PRIVATE_VAULT_SESSION:-}" != 1 ]; then
  exec "$dir/with-private-vault.sh" -- env PRIVATE_VAULT_SESSION=1 "$0" \
    --validator-set "$validator_set" --current-ca "$current_ca" \
    --previous-ca-output "$previous_ca_output" --new-ca-output "$new_ca_output"
fi
for command in vault kubectl jq openssl base64 install mktemp find seq tr python3 sed; do
  command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }
done
if [ ! -s "$current_ca" ] || ! openssl x509 -in "$current_ca" -noout >/dev/null 2>&1; then
  printf '%s\n' 'current public CA is not a certificate' >&2; exit 65
fi
for destination in "$previous_ca_output" "$new_ca_output"; do
  [ ! -e "$destination" ] && [ ! -L "$destination" ] || { printf 'refusing existing or symlink output: %s\n' "$destination" >&2; exit 65; }
  install -d -m 700 "$(dirname "$destination")"
done

namespace=validator-operations
deployment="validator-${validator_set}-client"
deployments_json="$(kubectl -n "$namespace" get deployments -o json)" || { printf '%s\n' 'cannot prove validator client deployment state' >&2; exit 69; }
replicas="$(jq -er --arg name "$deployment" '[.items[] | select(.metadata.name == $name) | (.spec.replicas // 0)] | if length == 0 then 0 elif length == 1 then .[0] else error("duplicate deployment") end' <<<"$deployments_json")" || { printf '%s\n' 'ambiguous validator client deployment state' >&2; exit 65; }
[ "$replicas" = 0 ] || { printf '%s\n' 'validator client must be scaled to zero before TLS rotation' >&2; exit 65; }
stateful_replicas="$(kubectl -n "$namespace" get statefulset "$deployment" --ignore-not-found -o jsonpath='{.spec.replicas}')" || { printf '%s\n' 'cannot prove validator client StatefulSet state' >&2; exit 69; }
[ -z "$stateful_replicas" ] || [ "$stateful_replicas" = 0 ] || { printf '%s\n' 'validator client StatefulSet must be scaled to zero before TLS rotation' >&2; exit 65; }
pods_json="$(kubectl -n "$namespace" get pods -l "app.kubernetes.io/component=validator-client,node-operator.io/validator-set=${validator_set}" -o json)" || { printf '%s\n' 'cannot prove validator client Pod absence' >&2; exit 69; }
jq -e '.items | length == 0' <<<"$pods_json" >/dev/null || { printf '%s\n' 'validator client Pod remains; TLS rotation refused' >&2; exit 65; }

scratch="$(mktemp -d /private/tmp/node-operator-signer-tls-rotation.XXXXXX)"; chmod 700 "$scratch"
root_token=''; child_token=''; child_accessor=''; ceremony_started=false; ceremony_complete=false; policy_created=false
policy_suffix="${scratch##*.}"; case "$policy_suffix" in ''|*[!A-Za-z0-9]*) printf '%s\n' 'invalid private scratch suffix' >&2; exit 70 ;; esac
policy_name="hoodi-${validator_set}-tls-rotation-${policy_suffix}"
cleanup() {
  original_status=$?; trap - EXIT; set +e; cleanup_failed=false
  if [ -n "$child_accessor" ] && ! VAULT_TOKEN="$root_token" vault token revoke -accessor "$child_accessor" >/dev/null 2>&1; then cleanup_failed=true; printf '%s\n' 'CRITICAL: child token revocation could not be confirmed' >&2; fi
  if [ "$policy_created" = true ] && ! VAULT_TOKEN="$root_token" vault policy delete "$policy_name" >/dev/null 2>&1; then cleanup_failed=true; printf '%s\n' 'CRITICAL: TLS rotation policy deletion could not be confirmed' >&2; fi
  if [ "$ceremony_complete" = true ] && [ -z "$root_token" ]; then cleanup_failed=true; printf '%s\n' 'CRITICAL: generated root token was not decoded or revoked' >&2
  elif [ -n "$root_token" ] && ! VAULT_TOKEN="$root_token" vault token revoke -self >/dev/null 2>&1; then cleanup_failed=true; printf '%s\n' 'CRITICAL: generated root token revocation could not be confirmed' >&2; fi
  if [ "$ceremony_started" = true ] && [ "$ceremony_complete" != true ] && ! vault operator generate-root -cancel >/dev/null 2>&1; then cleanup_failed=true; printf '%s\n' 'CRITICAL: root ceremony cancellation could not be confirmed' >&2; fi
  find "$scratch" -type f -exec sh -c 'chmod 600 "$1" 2>/dev/null; : > "$1"; rm -f "$1"' sh {} \; 2>/dev/null
  rmdir "$scratch" 2>/dev/null || true
  unset root_token child_token child_accessor VAULT_TOKEN
  [ "$cleanup_failed" = false ] || exit 70
  exit "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck source=scripts/ops/lib/vault-recovery-auth.sh
source "$dir/lib/vault-recovery-auth.sh"
vault_recovery_auth_preflight
status="$(vault operator generate-root -status -format=json)"
[ "$(jq -r .started <<<"$status")" = false ] || { printf '%s\n' 'root-token ceremony already in progress' >&2; exit 75; }
# Verify the local Vault v1.20 root-token decoder before a ceremony can start.
decoder='import base64,sys
encoded=sys.stdin.readline().rstrip("\n"); otp=sys.stdin.readline().rstrip("\n")
raw=base64.b64decode(encoded + "="*((4-len(encoded)%4)%4), validate=True)
if not otp or len(raw) != len(otp.encode()): raise SystemExit("root decode length mismatch")
sys.stdout.write(bytes(a ^ b for a,b in zip(raw,otp.encode())).decode())'
[ "$(printf '%s\n%s\n' 'Q15eRRxFXlpUXw' '1111111111' | python3 -c "$decoder")" = root-token ] || { printf '%s\n' 'local root-token decoder self-test failed' >&2; exit 69; }
initial="$(vault operator generate-root -init -format=json)"; ceremony_started=true
nonce="$(jq -er .nonce <<<"$initial")"; otp="$(jq -er .otp <<<"$initial")"; required="$(jq -er .required <<<"$initial")"
for number in $(seq 1 "$required"); do
  printf 'Recovery key share %s of %s: ' "$number" "$required" >&2
  IFS= read -r -s share; printf '\n' >&2
  reply="$(printf %s "$share" | vault operator generate-root -nonce="$nonce" -format=json -)"; unset share
  if [ "$(jq -r .complete <<<"$reply")" = true ]; then ceremony_complete=true; encoded="$(jq -er .encoded_token <<<"$reply")"; break; fi
done
[ "$ceremony_complete" = true ] || { printf '%s\n' 'recovery quorum was not reached' >&2; exit 77; }
# Vault v1.20 encodes XOR(token, raw OTP bytes) with unpadded base64. Feed
# both values through stdin so neither secret enters an external process argv.
case "$encoded:$otp" in *[$'\n\r']*) printf '%s\n' 'invalid multiline root decode input' >&2; exit 65 ;; esac
root_token="$(printf '%s\n%s\n' "$encoded" "$otp" | python3 -c "$decoder")"
unset encoded otp nonce initial reply status
policy_template="$dir/../../deploy/validator/vault/tls-rotation.hcl"
sed "s/REPLACE_WITH_VALIDATOR_SET/${validator_set}/g" "$policy_template" > "$scratch/tls-rotation.hcl"
VAULT_TOKEN="$root_token" vault policy write "$policy_name" "$scratch/tls-rotation.hcl" >/dev/null; policy_created=true
child_response="$(VAULT_TOKEN="$root_token" vault token create -orphan -no-default-policy -policy="$policy_name" -ttl=10m -format=json)"
child_token="$(jq -er '.auth.client_token' <<<"$child_response")"; child_accessor="$(jq -er '.auth.accessor' <<<"$child_response")"; unset child_response

base="kv/validators/hoodi/${validator_set}/runtime"
current_version="$(VAULT_TOKEN="$child_token" vault kv metadata get -format=json "$base/signer-tls" | jq -er '.data.current_version | select(type == "number" and . > 0)')"
service="validator-${validator_set}-remote-signer"
password_file="$scratch/pkcs12-password"; openssl rand -base64 48 | tr -d '\n' > "$password_file"; chmod 600 "$password_file"
openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 30 \
  -subj "/CN=${service}" \
  -addext "subjectAltName=DNS:${service},DNS:${service}.${namespace}.svc,DNS:${service}.${namespace}.svc.cluster.local" \
  -keyout "$scratch/tls.key" -out "$scratch/ca.crt" >/dev/null 2>&1
chmod 600 "$scratch/tls.key"
openssl pkcs12 -export -out "$scratch/tls.p12" -inkey "$scratch/tls.key" -in "$scratch/ca.crt" -passout "file:$password_file" >/dev/null 2>&1
password="$(<"$password_file")"
{ printf '{"pkcs12_b64":"'; base64 < "$scratch/tls.p12" | tr -d '\n'; printf '","password":"%s"}\n' "$password"; } > "$scratch/tls.json"
unset password
# Durable public rollback/reference artifacts exist before the one Vault write.
install -m 600 "$current_ca" "$previous_ca_output"
install -m 644 "$scratch/ca.crt" "$new_ca_output"
openssl x509 -in "$new_ca_output" -checkhost "${service}.${namespace}.svc" -noout | grep -Fq 'does match certificate' || { printf '%s\n' 'new signer certificate SAN verification failed' >&2; exit 65; }
VAULT_TOKEN="$child_token" vault kv put -cas="$current_version" "$base/signer-tls" @"$scratch/tls.json" >/dev/null
printf 'PASS: signer TLS CAS version %s rotated with DNS SANs; client remained at zero. Restart signer and verify with Go/Prysm before activation.\n' "$current_version"
