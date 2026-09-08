#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/deploy/dast/service-and-network-policies.yaml"
installer="$root/scripts/ops/install-private-dast-public-cas.sh"

grep -Fq 'name: prysm-beacon' "$manifest"
grep -Fq 'name: validator-signer-upcheck-proxy' "$manifest"
grep -Fq "upstream = 'validator-hoodi-001-remote-signer'" "$manifest"
if grep -Fq 'validator-hoodi-001-remote-signer.validator-operations.svc' "$manifest"; then
  printf 'proxy hostname must match the certificate CN while the certificate has no SAN\n' >&2
  exit 1
fi
grep -Fq "if self.path != '/upcheck': self.send_error(404); return" "$manifest"
grep -Fq 'def do_POST(self): self.send_error(405)' "$manifest"
grep -Fq 'port: 8080' "$manifest"
ruby -ryaml -e '
  documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
  dast_egress = documents.find { |document| document.dig("kind") == "NetworkPolicy" && document.dig("metadata", "name") == "allow-private-dast-egress" }
  abort("missing DAST egress policy") unless dast_egress
  ports = dast_egress.dig("spec", "egress").flat_map { |rule| rule.fetch("ports", []).map { |port| port["port"] } }
  abort("DAST egress reaches signer 9000") if ports.include?(9000)
  signer = documents.find { |document| document.dig("kind") == "NetworkPolicy" && document.dig("metadata", "name") == "signer-upcheck-proxy-to-signer" }
  abort("missing signer proxy ingress policy") unless signer
  sources = signer.dig("spec", "ingress").flat_map { |rule| rule.fetch("from", []) }
  abort("DAST namespace reaches signer") if sources.any? { |source| source.dig("namespaceSelector", "matchLabels", "node-operator.io/dast-client") == "true" }
' "$manifest"
grep -Fq 'cat /vault/userconfig/vault-tls/ca.crt' "$installer"
grep -Fq 'PRIVATE KEY' "$installer"
grep -Fq 'openssl x509 -in "$vault_ca" -out "$vault_certificate"' "$installer"
grep -Fq 'openssl x509 -in "$signer_ca" -out "$signer_certificate"' "$installer"
if grep -Ev '^[[:space:]]*#' "$installer" | grep -Eq 'get[[:space:]]+secret|VAULT_TOKEN|JWT'; then
  printf 'public CA installer must not access secret material\n' >&2
  exit 1
fi
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$scratch/key.pem" -out "$scratch/cert.pem" -subj /CN=test-dast-ca -days 1 >/dev/null 2>&1
cat "$scratch/cert.pem" "$scratch/key.pem" > "$scratch/mixed.pem"
mkdir -p "$scratch/bin"
cat > "$scratch/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' exec '* ]]; then cat "$TEST_VAULT_CA"; else cat >/dev/null; fi
EOF
chmod 0755 "$scratch/bin/kubectl"
if TEST_VAULT_CA="$scratch/cert.pem" PRIVATE_EKS_SESSION=1 PATH="$scratch/bin:$PATH" "$installer" --signer-ca "$scratch/mixed.pem" >/dev/null 2>&1; then
  printf 'installer accepted a PEM containing a private key\n' >&2
  exit 1
fi
printf 'PASS private DAST access is limited to a fixed signer upcheck proxy and public CA trust anchors.\n'
