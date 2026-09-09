#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/rotate-hoodi-validator-signer-tls.sh"
fail() { printf 'FAIL signer TLS rotation contract: %s\n' "$*" >&2; exit 1; }
test -x "$script" || fail 'rotation helper missing or not executable'
bash -n "$script"
grep -Fq 'validator client must be scaled to zero' "$script" || fail 'zero-client gate missing'
# Literal source assertions.
# shellcheck disable=SC2016
grep -Fq 'vault kv put -cas="$current_version" "$base/signer-tls"' "$script" || fail 'TLS-only CAS write missing'
if grep -Eq 'kv put.*(keystore|slashing-db-password)|kv get' "$script"; then fail 'rotation helper can read/write custody or slashing records'; fi
# shellcheck disable=SC2016
grep -Fq 'subjectAltName=DNS:${service},DNS:${service}.${namespace}.svc,DNS:${service}.${namespace}.svc.cluster.local' "$script" || fail 'required signer SANs missing'
# shellcheck disable=SC2016
grep -Fq 'passout "file:$password_file"' "$script" || fail 'PKCS12 password could enter process arguments'
grep -Fq 'vault token revoke -self' "$script" || fail 'generated root token is not revoked'
grep -Fq 'tls-rotation.hcl' "$script" || fail 'narrow TLS-only policy is not used'
# shellcheck disable=SC2016
grep -Fq 'kubectl -n "$namespace" get deployments -o json' "$script" || fail 'deployment API failures could be masked as absence'
# shellcheck disable=SC2016
if grep -Eq '(--arg (encoded|otp)|generate-root -decode=\$encoded|generate-root -decode="\$encoded")' "$script"; then fail 'root decode material enters process argv'; fi

scratch="$(mktemp -d /private/tmp/node-operator-signer-san.XXXXXX)"; trap 'rm -rf "$scratch"' EXIT
command -v go >/dev/null 2>&1 || fail 'Go is required for Prysm-compatible hostname verification'
service=validator-hoodi-001-remote-signer
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -subj "/CN=$service" \
  -addext "subjectAltName=DNS:${service},DNS:${service}.validator-operations.svc,DNS:${service}.validator-operations.svc.cluster.local" \
  -keyout "$scratch/key" -out "$scratch/cert" >/dev/null 2>&1
openssl x509 -in "$scratch/cert" -checkhost "${service}.validator-operations.svc" -noout | grep -Fq 'does match certificate' || fail 'generated SAN is not hostname-valid'
openssl x509 -in "$scratch/cert" -ext subjectAltName -noout | grep -Fq "DNS:${service}.validator-operations.svc.cluster.local" || fail 'cluster-local SAN missing'
cat > "$scratch/verify.go" <<'EOF'
package main
import ("crypto/x509"; "encoding/pem"; "os")
func main() {
  raw, err := os.ReadFile(os.Args[1]); if err != nil { panic(err) }
  block, _ := pem.Decode(raw); if block == nil { panic("no certificate") }
  cert, err := x509.ParseCertificate(block.Bytes); if err != nil { panic(err) }
  if err := cert.VerifyHostname(os.Args[2]); err != nil { panic(err) }
}
EOF
go run "$scratch/verify.go" "$scratch/cert" "${service}.validator-operations.svc" || fail 'Go/Prysm hostname verification failed'

mkdir -p "$scratch/bin"
cat > "$scratch/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${MOCK_KUBE_MODE:-ok}" != fail ] || exit 1
case "$*" in
  '-n validator-operations get statefulset validator-hoodi-001-client --ignore-not-found -o jsonpath={.spec.replicas}')
    [ "${MOCK_STATEFUL_FAIL:-false}" = false ] || exit 1
    printf '%s' "${MOCK_STATEFUL_REPLICAS:-0}" ;;
  '-n validator-operations get deployments -o json')
    jq -n --argjson replicas "${MOCK_REPLICAS:-0}" '{items:(if $replicas < 0 then [] else [{metadata:{name:"validator-hoodi-001-client"},spec:{replicas:$replicas}}] end)}' ;;
  '-n validator-operations get pods -l app.kubernetes.io/component=validator-client,node-operator.io/validator-set=hoodi-001 -o json')
    jq -n --argjson count "${MOCK_PODS:-0}" '{items:[range(0;$count)|{metadata:{name:("client-"+tostring)}}]}' ;;
  *) exit 64 ;;
esac
EOF
cat > "$scratch/bin/vault" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_VAULT_TRACE"
case "$*" in
  'operator generate-root -status -format=json') printf '%s\n' '{"started":false}' ;;
  'operator generate-root -init -format=json') jq -n --arg otp "$MOCK_OTP" '{nonce:"nonce",otp:$otp,required:1}' ;;
  'operator generate-root -nonce=nonce -format=json -') IFS= read -r _ || true; jq -n --arg encoded "$MOCK_ENCODED" '{complete:true,encoded_token:$encoded}' ;;
  'policy write hoodi-hoodi-001-tls-rotation-'*) ;;
  'token create -orphan -no-default-policy -policy=hoodi-hoodi-001-tls-rotation-'*'-ttl=10m -format=json') printf '%s\n' '{"auth":{"client_token":"child-token","accessor":"child-accessor"}}' ;;
  'kv metadata get -format=json kv/validators/hoodi/hoodi-001/runtime/signer-tls') printf '%s\n' '{"data":{"current_version":4}}' ;;
  'kv put -cas=4 kv/validators/hoodi/hoodi-001/runtime/signer-tls '@*) [ "${MOCK_CAS_FAIL:-false}" = false ] ;;
  'token revoke -accessor child-accessor'|'policy delete hoodi-hoodi-001-tls-rotation-'*) ;;
  'token revoke -self') [ "${MOCK_ROOT_REVOKE_FAIL:-false}" = false ] ;;
  'operator generate-root -cancel') ;;
  *) printf 'unexpected vault call: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$scratch/bin/kubectl" "$scratch/bin/vault"
mock_otp='1111111111'
mock_encoded="$(python3 -c 'import base64; token=b"root-token"; otp=b"1111111111"; print(base64.b64encode(bytes(x^y for x,y in zip(token,otp))).decode().rstrip("="))')"
run_helper() {
  printf '%s\n' 'synthetic-share' | PATH="$scratch/bin:$PATH" PRIVATE_VAULT_SESSION=1 MOCK_VAULT_TRACE="$scratch/vault.trace" MOCK_OTP="$mock_otp" MOCK_ENCODED="$mock_encoded" "$script" \
    --validator-set hoodi-001 --current-ca "$scratch/cert" --previous-ca-output "$1" --new-ca-output "$2"
}

: > "$scratch/vault.trace"
if MOCK_KUBE_MODE=fail run_helper "$scratch/api-old" "$scratch/api-new" >/dev/null 2>&1; then fail 'Kubernetes API failure was treated as client absence'; fi
test ! -s "$scratch/vault.trace" || fail 'Vault ceremony began after Kubernetes API failure'
if MOCK_REPLICAS=1 run_helper "$scratch/live-old" "$scratch/live-new" >/dev/null 2>&1; then fail 'live client replica did not block rotation'; fi
if MOCK_PODS=1 run_helper "$scratch/pod-old" "$scratch/pod-new" >/dev/null 2>&1; then fail 'remaining client Pod did not block rotation'; fi
if MOCK_STATEFUL_REPLICAS=1 run_helper "$scratch/stateful-old" "$scratch/stateful-new" >/dev/null 2>&1; then fail 'desired StatefulSet replica without Pods did not block rotation'; fi
if MOCK_STATEFUL_FAIL=true run_helper "$scratch/stateful-api-old" "$scratch/stateful-api-new" >/dev/null 2>&1; then fail 'StatefulSet API failure did not block rotation'; fi
test ! -s "$scratch/vault.trace" || fail 'Vault ceremony began before all controller gates passed'

: > "$scratch/vault.trace"
if ! run_helper "$scratch/previous-ca" "$scratch/new-ca" >"$scratch/helper.out" 2>&1; then
  sed -n '1,20p' "$scratch/helper.out" >&2
  sed -n '1,30p' "$scratch/vault.trace" >&2
  fail 'mocked TLS-only rotation did not complete'
fi
if ! test -s "$scratch/previous-ca" || ! test -s "$scratch/new-ca"; then fail 'public CA recovery artifacts were not preserved'; fi
for action in 'policy write hoodi-hoodi-001-tls-rotation-' 'kv metadata get -format=json kv/validators/hoodi/hoodi-001/runtime/signer-tls' 'kv put -cas=4 kv/validators/hoodi/hoodi-001/runtime/signer-tls' 'token revoke -accessor child-accessor' 'policy delete hoodi-hoodi-001-tls-rotation-' 'token revoke -self'; do
  grep -Fq "$action" "$scratch/vault.trace" || fail "missing lifecycle action: $action"
done
if grep -Eq 'keystore|slashing-db-password|runtime/password' "$scratch/vault.trace"; then fail 'mocked execution touched non-TLS custody records'; fi

: > "$scratch/vault.trace"
if MOCK_CAS_FAIL=true run_helper "$scratch/cas-old" "$scratch/cas-new" >/dev/null 2>&1; then fail 'CAS failure unexpectedly passed'; fi
if ! test -s "$scratch/cas-old" || ! test -s "$scratch/cas-new"; then fail 'CAS failure lacked durable public recovery artifacts'; fi
grep -Fq 'token revoke -self' "$scratch/vault.trace" || fail 'CAS failure did not revoke root token'

: > "$scratch/vault.trace"
if MOCK_ROOT_REVOKE_FAIL=true run_helper "$scratch/revoke-old" "$scratch/revoke-new" >/dev/null 2>&1; then fail 'unconfirmed root revocation unexpectedly passed'; fi
grep -Fq 'token revoke -self' "$scratch/vault.trace" || fail 'root revocation failure was not exercised'
printf '%s\n' 'PASS signer TLS rotation is TLS-only, CAS-guarded, client-zero-gated, SAN-valid, and keeps passwords out of argv.'
