#!/usr/bin/env bash
set -euo pipefail

usage() { printf 'Usage: %s --signer-ca <absolute-public-pem>\n' "${0##*/}" >&2; exit 64; }
signer_ca=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --signer-ca) signer_ca="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$signer_ca" = /* && -f "$signer_ca" ]] || usage

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [ "${PRIVATE_EKS_SESSION:-}" != 1 ]; then
  exec "$root/scripts/ops/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 "$0" --signer-ca "$signer_ca"
fi

for command in kubectl openssl mktemp; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
vault_ca="$(mktemp "${TMPDIR:-/tmp}/node-operator-dast-vault-ca.XXXXXX")"
vault_certificate="$(mktemp "${TMPDIR:-/tmp}/node-operator-dast-vault-certificate.XXXXXX")"
signer_certificate="$(mktemp "${TMPDIR:-/tmp}/node-operator-dast-signer-certificate.XXXXXX")"
cleanup() { rm -f "$vault_ca" "$vault_certificate" "$signer_certificate"; }
trap cleanup EXIT

# The mounted Vault CA is public trust material. This command never reads a
# Kubernetes Secret object, a Vault token, a private key, or a signer key.
kubectl -n vault exec vault-0 -- sh -c 'cat /vault/userconfig/vault-tls/ca.crt' > "$vault_ca"
for source in "$vault_ca" "$signer_ca"; do
  if grep -Eq -- '-----BEGIN ([A-Z ]* )?PRIVATE KEY-----' "$source"; then
    printf 'refusing PEM that contains a private key\n' >&2
    exit 1
  fi
done
# Canonicalize only a parsed X.509 certificate into the ConfigMap. This
# prevents trailing non-certificate material from entering the DAST namespace.
openssl x509 -in "$vault_ca" -out "$vault_certificate"
openssl x509 -in "$signer_ca" -out "$signer_certificate"
for spec in "private-dast-vault-ca=$vault_certificate" "private-dast-signer-ca=$signer_certificate"; do
  name="${spec%%=*}"
  file="${spec#*=}"
  kubectl -n node-operator-dast create configmap "$name" --from-file=ca.crt="$file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
# The GET-only signer proxy runs beside the signer, not in the scanner
# namespace. Supply the same parsed public certificate to its declared mount.
kubectl -n validator-operations create configmap validator-hoodi-001-signer-ca --from-file=ca.crt="$signer_certificate" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
printf 'PASS: installed only public Vault and signer CA trust anchors for private DAST.\n'
