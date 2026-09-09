#!/usr/bin/env bash
set -euo pipefail

# Creates NEW transport-only identities. Never reads or changes BLS custody.
usage() { printf 'Usage: %s --validator-set <hoodi-id> --public-ca-output <new-absolute-file> [--dry-run]\n' "${0##*/}" >&2; exit 64; }
validator_set=''; public_ca=''; dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --public-ca-output) public_ca="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done
[[ "$validator_set" =~ ^hoodi-[a-z0-9][a-z0-9-]{0,35}$ ]] || usage
case "$public_ca" in /*) ;; *) usage ;; esac
[ ! -e "$public_ca" ] && [ ! -L "$public_ca" ] || { printf '%s\n' 'Public CA output must be new.' >&2; exit 65; }
for command in kubectl openssl jq mktemp rm mkdir chmod cp date; do command -v "$command" >/dev/null || exit 69; done
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ "${PRIVATE_EKS_SESSION:-}" != 1 ]; then
  args=(--validator-set "$validator_set" --public-ca-output "$public_ca")
  [ "$dry_run" != true ] || args+=(--dry-run)
  exec "$dir/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 "$0" "${args[@]}"
fi
namespace=validator-operations
client="validator-${validator_set}-client-tls"
server="validator-${validator_set}-signer-tls"
known="validator-${validator_set}-known-clients"
hostname="validator-${validator_set}-remote-signer.${namespace}.svc"
client_cn="validator-${validator_set}-client"
for secret_name in "$client" "$server"; do
  existing="$(kubectl -n "$namespace" get secret "$secret_name" --ignore-not-found -o name)"
  [ -z "$existing" ] || { printf '%s\n' 'Transport Secret already exists; use a separately reviewed rotation.' >&2; exit 65; }
done
existing="$(kubectl -n "$namespace" get configmap "$known" --ignore-not-found -o name)"
[ -z "$existing" ] || { printf '%s\n' 'Known-clients ConfigMap already exists.' >&2; exit 65; }
umask 077
scratch="$(mktemp -d /private/tmp/hoodi-transport-tls.XXXXXX)"
created=false
cleanup() {
  result=$?
  trap - EXIT
  rm -rf "$scratch"
  if [ "$result" -ne 0 ] && [ "$created" = true ]; then
    printf '%s\n' 'CRITICAL: partial transport provisioning; no automatic overwrite or rollback. Inspect exact named resources before retry.' >&2
    exit 70
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 30 -subj "/CN=${validator_set}-transport-ca" -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' -keyout "$scratch/ca.key" -out "$scratch/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:3072 -nodes -sha256 -subj "/CN=$hostname" -keyout "$scratch/server.key" -out "$scratch/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s,DNS:%s.cluster.local,DNS:validator-%s-remote-signer\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\nbasicConstraints=CA:FALSE\n' "$hostname" "$hostname" "$validator_set" > "$scratch/server.ext"
openssl x509 -req -in "$scratch/server.csr" -CA "$scratch/ca.crt" -CAkey "$scratch/ca.key" -set_serial 2 -days 30 -sha256 -extfile "$scratch/server.ext" -out "$scratch/server.crt" >/dev/null 2>&1
openssl req -newkey rsa:3072 -nodes -sha256 -subj "/CN=$client_cn" -keyout "$scratch/client.key" -out "$scratch/client.csr" >/dev/null 2>&1
printf 'extendedKeyUsage=clientAuth\nkeyUsage=digitalSignature\nbasicConstraints=CA:FALSE\n' > "$scratch/client.ext"
openssl x509 -req -in "$scratch/client.csr" -CA "$scratch/ca.crt" -CAkey "$scratch/ca.key" -set_serial 3 -days 30 -sha256 -extfile "$scratch/client.ext" -out "$scratch/client.crt" >/dev/null 2>&1
openssl verify -CAfile "$scratch/ca.crt" -purpose sslserver -verify_hostname "$hostname" "$scratch/server.crt" >/dev/null
openssl verify -CAfile "$scratch/ca.crt" -purpose sslclient "$scratch/client.crt" >/dev/null
openssl rand -hex 32 > "$scratch/tls-password.txt"
openssl pkcs12 -export -inkey "$scratch/server.key" -in "$scratch/server.crt" -certfile "$scratch/ca.crt" -name "$hostname" -out "$scratch/tls.p12" -passout "file:$scratch/tls-password.txt"
fingerprint="$(openssl x509 -in "$scratch/client.crt" -noout -fingerprint -sha256)"
fingerprint="${fingerprint#*=}"
[[ "$fingerprint" =~ ^([A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$ ]] || exit 65
printf '%s %s\n' "$client_cn" "$fingerprint" > "$scratch/known-clients.txt"
if [ "$dry_run" = true ]; then printf '%s\n' 'PASS synthetic transport certificate generation and hostname/EKU checks; no Kubernetes resources changed.'; exit 0; fi
mkdir -p "$(dirname "$public_ca")"
# Preserve public recovery material before any cluster mutation; no private
# material is copied outside scratch or printed in command output.
(set -o noclobber; printf '' > "$public_ca")
cp "$scratch/ca.crt" "$public_ca"
created=true
kubectl -n "$namespace" create secret generic "$server" --from-file="tls.p12=$scratch/tls.p12" --from-file="tls-password.txt=$scratch/tls-password.txt" >/dev/null
kubectl -n "$namespace" create secret generic "$client" --from-file="tls.crt=$scratch/client.crt" --from-file="tls.key=$scratch/client.key" --from-file="ca.crt=$scratch/ca.crt" >/dev/null
kubectl -n "$namespace" create configmap "$known" --from-file="known-clients=$scratch/known-clients.txt" >/dev/null
for secret_name in "$client" "$server"; do
  kubectl -n "$namespace" label secret "$secret_name" "node-operator.io/validator-set=$validator_set" 'node-operator.io/purpose=transport-tls' >/dev/null
done
kubectl -n "$namespace" label configmap "$known" "node-operator.io/validator-set=$validator_set" >/dev/null
verify_inventory() {
  local kind="$1" resource="$2" expected_keys="$3" inventory
  # Render names/metadata and key names only. Never emit Secret values.
  # kubectl Go-template variables, not shell variables.
  # shellcheck disable=SC2016
  inventory="$(kubectl -n "$namespace" get "$kind" "$resource" -o 'go-template={{.metadata.name}}|{{.metadata.uid}}|{{.metadata.resourceVersion}}|{{range $key, $value := .data}}{{$key}},{{end}}')"
  IFS='|' read -r observed_name observed_uid observed_version observed_keys <<< "$inventory"
  [ "$observed_name" = "$resource" ] && [ -n "$observed_uid" ] && [ -n "$observed_version" ] && [ "$observed_keys" = "$expected_keys" ] || {
    printf 'Transport resource inventory verification failed: %s/%s\n' "$kind" "$resource" >&2
    return 65
  }
}
verify_inventory secret "$server" 'tls-password.txt,tls.p12,'
verify_inventory secret "$client" 'ca.crt,tls.crt,tls.key,'
verify_inventory configmap "$known" 'known-clients,'
printf 'PASS transport-only TLS resources created for %s; public CA: %s. No workloads were restarted.\n' "$validator_set" "$public_ca"
