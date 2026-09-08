#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="$root/deploy/dast/service-and-network-policies.yaml"
installer="$root/scripts/ops/install-private-dast-public-cas.sh"

grep -Fq 'name: prysm-beacon' "$manifest"
for label in 'pod-security.kubernetes.io/enforce: restricted' 'pod-security.kubernetes.io/enforce-version: v1.35' 'pod-security.kubernetes.io/audit: restricted' 'pod-security.kubernetes.io/warn: restricted'; do
  grep -Fq "$label" "$manifest"
done
grep -Fq 'name: validator-signer-upcheck-proxy' "$manifest"
grep -Fq 'name: nethermind-upcheck-proxy' "$manifest"
grep -Fq "upstream = 'nethermind-execution'" "$manifest"
grep -Fq "socket.create_connection((upstream, 30303), timeout=5)" "$manifest"
grep -Fq "upstream = 'validator-hoodi-001-remote-signer'" "$manifest"
if grep -Fq 'validator-hoodi-001-remote-signer.validator-operations.svc' "$manifest"; then
  printf 'proxy hostname must match the certificate CN while the certificate has no SAN\n' >&2
  exit 1
fi
grep -Fq "if self.path != '/upcheck': self.send_error(404); return" "$manifest"
grep -Fq 'def do_POST(self): self.send_error(405)' "$manifest"
grep -Fq 'def do_PATCH(self): self.send_error(405)' "$manifest"
grep -Fq 'if conn is not None: conn.close()' "$manifest"
grep -Fq 'port: 8080' "$manifest"
ruby -ryaml -e '
  documents = YAML.load_stream(File.read(ARGV.fetch(0))).compact
  dast_egress = documents.find { |document| document.dig("kind") == "NetworkPolicy" && document.dig("metadata", "name") == "allow-private-dast-egress" }
  abort("missing DAST egress policy") unless dast_egress
  ports = dast_egress.dig("spec", "egress").flat_map { |rule| rule.fetch("ports", []).map { |port| port["port"] } }
  abort("DAST egress reaches signer 9000") if ports.include?(9000)
  abort("DAST reaches Nethermind Engine API") if ports.include?(8551)
  abort("DAST reaches Nethermind P2P directly") if ports.include?(30303)
  signer = documents.find { |document| document.dig("kind") == "NetworkPolicy" && document.dig("metadata", "name") == "signer-upcheck-proxy-to-signer" }
  abort("missing signer proxy ingress policy") unless signer
  sources = signer.dig("spec", "ingress").flat_map { |rule| rule.fetch("from", []) }
  abort("DAST namespace reaches signer") if sources.any? { |source| source.dig("namespaceSelector", "matchLabels", "node-operator.io/dast-client") == "true" }

  proxies = documents.select { |document| document.dig("kind") == "Deployment" && ["nethermind-upcheck-proxy", "validator-signer-upcheck-proxy"].include?(document.dig("metadata", "name")) }
  abort("missing DAST upcheck proxies") unless proxies.length == 2
  proxies.each do |proxy|
    container = proxy.dig("spec", "template", "spec", "containers")&.fetch(0)
    abort("#{proxy.dig("metadata", "name")} must explicitly disable privilege") unless container&.dig("securityContext", "privileged") == false
  end

  nethermind = documents.find { |document| document.dig("kind") == "Service" && document.dig("metadata", "namespace") == "node-operator" && document.dig("metadata", "name") == "nethermind-execution" }
  abort("missing fixed Nethermind P2P Service") unless nethermind
  abort("wrong Nethermind P2P selector") unless nethermind.dig("spec", "selector") == {"app.kubernetes.io/name" => "nethermind"}
  ports = nethermind.dig("spec", "ports")
  abort("Nethermind Service must expose only TCP P2P 30303") unless ports == [{"name" => "p2p-tcp", "port" => 30303, "targetPort" => "p2p-tcp", "protocol" => "TCP"}]
' "$manifest"
grep -Fq 'cat /vault/userconfig/vault-tls/ca.crt' "$installer"
grep -Fq 'PRIVATE KEY' "$installer"
# shellcheck disable=SC2016 # Assert literal commands in the installer contract.
grep -Fq 'openssl x509 -in "$vault_ca" -out "$vault_certificate"' "$installer"
# shellcheck disable=SC2016 # Assert literal commands in the installer contract.
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
if [[ " $* " == *' exec '* ]]; then
  cat "$TEST_VAULT_CA"
elif [[ " $* " == *' create configmap '* ]]; then
  printf '%s\n' "$*" >> "$TEST_KUBECTL_CALLS"
  for argument in "$@"; do
    if [[ "$argument" == --from-file=ca.crt=* ]]; then
      file="${argument#--from-file=ca.crt=}"
      openssl x509 -in "$file" -noout >/dev/null
      ! grep -q 'PRIVATE KEY' "$file"
    fi
  done
  printf 'public-configmap-fixture\n'
else
  cat >/dev/null
fi
EOF
chmod 0755 "$scratch/bin/kubectl"
if TEST_VAULT_CA="$scratch/cert.pem" PRIVATE_EKS_SESSION=1 PATH="$scratch/bin:$PATH" "$installer" --signer-ca "$scratch/mixed.pem" >/dev/null 2>&1; then
  printf 'installer accepted a PEM containing a private key\n' >&2
  exit 1
fi
TEST_KUBECTL_CALLS="$scratch/calls" TEST_VAULT_CA="$scratch/cert.pem" PRIVATE_EKS_SESSION=1 PATH="$scratch/bin:$PATH" "$installer" --signer-ca "$scratch/cert.pem" >/dev/null
test "$(wc -l < "$scratch/calls" | tr -d ' ')" = 3
for expected in \
  '-n node-operator-dast create configmap private-dast-vault-ca --from-file=ca.crt=' \
  '-n node-operator-dast create configmap private-dast-signer-ca --from-file=ca.crt=' \
  '-n validator-operations create configmap validator-hoodi-001-signer-ca --from-file=ca.crt='; do
  grep -Fq -- "$expected" "$scratch/calls"
done

# Execute the actual embedded proxy implementation with a fake TLS upstream.
# The server start line is excluded; every handler method is exercised below.
proxy_code="$(awk '
  /              import http\.client, ssl/ { capture=1 }
  capture && /              HTTPServer\(\('\''0\.0\.0\.0'\'', 8080\), Handler\)\.serve_forever\(\)/ { exit }
  capture { sub(/^              /, ""); print }
' "$manifest")"
PROXY_CODE="$proxy_code" python3 - <<'PY'
import http.client
import os
import ssl

calls = []
closed = []
class Response:
    status = 200
    def read(self, size):
        assert size == 0
class Connection:
    def __init__(self, host, port, context, timeout):
        assert host == 'validator-hoodi-001-remote-signer'
        assert port == 9000 and timeout == 5
    def request(self, method, path): calls.append((method, path))
    def getresponse(self): return Response()
    def close(self): closed.append(True)

http.client.HTTPSConnection = Connection
ssl.create_default_context = lambda cafile: object()
scope = {}
exec(os.environ['PROXY_CODE'], scope)
Handler = scope['Handler']

def invoke(method, path):
    handler = object.__new__(Handler)
    handler.path = path
    events = []
    handler.send_response = lambda status: events.append(('response', status))
    handler.end_headers = lambda: events.append(('end',))
    handler.send_error = lambda status: events.append(('error', status))
    getattr(handler, method)()
    return events

assert invoke('do_GET', '/upcheck') == [('response', 200), ('end',)]
assert calls == [('GET', '/upcheck')] and closed == [True]
for method in ('do_POST', 'do_PUT', 'do_DELETE', 'do_PATCH'):
    assert invoke(method, '/upcheck') == [('error', 405)]
assert invoke('do_GET', '/api/v1/eth2/sign/0x00') == [('error', 404)]
assert calls == [('GET', '/upcheck')]
PY

# Execute the fixed Nethermind reachability proxy. It may establish and close
# a TCP connection but must never send application bytes or expose JSON-RPC.
nethermind_proxy_code="$(awk '
  /              import socket/ { capture=1 }
  capture && /              HTTPServer\(\('\''0\.0\.0\.0'\'', 8080\), Handler\)\.serve_forever\(\)/ { exit }
  capture { sub(/^              /, ""); print }
' "$manifest")"
NETHERMIND_PROXY_CODE="$nethermind_proxy_code" python3 - <<'PY'
import os
import socket

connections = []
class Connection:
    def close(self): connections.append('closed')
def create_connection(address, timeout):
    assert address == ('nethermind-execution', 30303)
    assert timeout == 5
    connections.append('connected')
    return Connection()
socket.create_connection = create_connection
scope = {}
exec(os.environ['NETHERMIND_PROXY_CODE'], scope)
Handler = scope['Handler']

def invoke(method, path):
    handler = object.__new__(Handler)
    handler.path = path
    events = []
    handler.send_response = lambda status: events.append(('response', status))
    handler.end_headers = lambda: events.append(('end',))
    handler.send_error = lambda status: events.append(('error', status))
    getattr(handler, method)()
    return events

assert invoke('do_GET', '/upcheck') == [('response', 200), ('end',)]
assert connections == ['connected', 'closed']
for method in ('do_POST', 'do_PUT', 'do_DELETE', 'do_PATCH'):
    assert invoke(method, '/upcheck') == [('error', 405)]
assert invoke('do_GET', '/jsonrpc') == [('error', 404)]
assert connections == ['connected', 'closed']
PY
if [ -n "${KYVERNO_BIN:-}" ] || command -v kyverno >/dev/null 2>&1; then
  bash "$root/scripts/ci/test-kyverno-workload-baseline.sh"
else
  printf 'SKIP: Kyverno CLI is unavailable; standalone real-engine fixture suite remains required.\n'
fi
printf 'PASS private DAST access is limited to a fixed signer upcheck proxy and public CA trust anchors.\n'
