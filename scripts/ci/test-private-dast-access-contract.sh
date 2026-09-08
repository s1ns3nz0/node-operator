#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/deploy/dast/service-and-network-policies.yaml"
installer="$root/scripts/ops/install-private-dast-public-cas.sh"

grep -Fq 'name: prysm-beacon' "$manifest"
grep -Fq 'name: validator-signer-upcheck-proxy' "$manifest"
grep -Fq "if self.path != '/upcheck': self.send_error(404); return" "$manifest"
grep -Fq 'def do_POST(self): self.send_error(405)' "$manifest"
grep -Fq 'port: 8080' "$manifest"
if grep -Fq 'allow-private-dast-signer-upcheck-ingress' "$manifest" || grep -Fq 'port: 9000}]\n    - to:' "$manifest"; then
  printf 'DAST must not receive a direct remote-signer ingress path\n' >&2
  exit 1
fi
grep -Fq 'cat /vault/userconfig/vault-tls/ca.crt' "$installer"
if grep -Ev '^[[:space:]]*#' "$installer" | grep -Eq 'get[[:space:]]+secret|vault token|JWT|private key'; then
  printf 'public CA installer must not access secret material\n' >&2
  exit 1
fi
printf 'PASS private DAST access is limited to a fixed signer upcheck proxy and public CA trust anchors.\n'
