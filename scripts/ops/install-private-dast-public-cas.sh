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
vault_ca="$(mktemp /private/tmp/node-operator-dast-vault-ca.XXXXXX)"
cleanup() { rm -f "$vault_ca"; }
trap cleanup EXIT

# The mounted Vault CA is public trust material. This command never reads a
# Kubernetes Secret object, a Vault token, a private key, or a signer key.
kubectl -n vault exec vault-0 -- sh -c 'cat /vault/userconfig/vault-tls/ca.crt' > "$vault_ca"
openssl x509 -in "$vault_ca" -noout >/dev/null
openssl x509 -in "$signer_ca" -noout >/dev/null
for spec in "private-dast-vault-ca=$vault_ca" "private-dast-signer-ca=$signer_ca"; do
  name="${spec%%=*}"
  file="${spec#*=}"
  kubectl -n node-operator-dast create configmap "$name" --from-file=ca.crt="$file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
printf 'PASS: installed only public Vault and signer CA trust anchors for private DAST.\n'
