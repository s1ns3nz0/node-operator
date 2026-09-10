#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
renderer="$root/scripts/ops/render-hoodi-validator-runtime.sh"
tmp="$(mktemp -d /private/tmp/node-operator-runtime-render.XXXXXX)"
web3signer='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-web3signer@sha256:9a20e02a5821ad72fd318fa2a3ec0158a9a5acd9db80aa9214e9cc991ad4dbc3'
postgres='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-postgres@sha256:030da09481c3876b71a7e49738a932e1c18c398201a1e4ccfdbff1e5a541215b'
"$renderer" --validator-set hoodi-test-001 --aws-account-id 106760547719 --web3signer-image "$web3signer" --postgres-image "$postgres" --output "$tmp/runtime.yaml" >/dev/null
if "$renderer" --validator-set hoodi-test-001 --aws-account-id 999999999999 --web3signer-image "$web3signer" --postgres-image "$postgres" --output "$tmp/wrong-account.yaml" >/dev/null 2>&1; then
  printf '%s\n' 'runtime renderer accepted images from another AWS account' >&2
  exit 1
fi
grep -Fq 'POSTGRES_PASSWORD_FILE' "$tmp/runtime.yaml"
grep -Fq 'persistentVolumeClaimRetentionPolicy:' "$tmp/runtime.yaml"
grep -Fq 'name: PGDATA, value: /var/lib/postgresql/data/pgdata' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-db-dependencies' "$tmp/runtime.yaml"
grep -Fq 'readOnlyRootFilesystem: true' "$tmp/runtime.yaml"
grep -Fq 'limits: {cpu: "2", memory: 4Gi}' "$tmp/runtime.yaml"
grep -Fq -- '--tls-keystore-file=/vault/secrets/tls.p12' "$tmp/runtime.yaml"
grep -Fq -- '--tls-keystore-password-file=/vault/secrets/tls-password.txt' "$tmp/runtime.yaml"
grep -Fq -- '--access-logs-enabled' "$tmp/runtime.yaml"
if grep -Fq 'secretName: validator-hoodi-test-001-signer-tls' "$tmp/runtime.yaml"; then printf '%s\n' 'signer TLS remained a Kubernetes Secret' >&2; exit 1; fi
grep -Fq -- '--tls-known-clients-file=/etc/web3signer-known-clients/known-clients.txt' "$tmp/runtime.yaml"
grep -Fq 'name: validator-hoodi-test-001-known-clients' "$tmp/runtime.yaml"
if grep -Fq -- '--tls-allow-any-client' "$tmp/runtime.yaml"; then printf '%s\n' 'allow-any TLS client mode found' >&2; exit 1; fi
grep -Fq 'agent-inject-template-tls.p12' "$tmp/runtime.yaml"
grep -Fq -- '--slashing-protection-pruning-db-pool-configuration-file=/vault/secrets/slashing-db.properties' "$tmp/runtime.yaml"
grep -Fq 'vault.hashicorp.com/agent-inject-secret-keystore.json' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-remote-signer' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-primary' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-signer-ingress' "$tmp/runtime.yaml"
grep -Fq 'node-operator.io/validator-set: hoodi-test-001' "$tmp/runtime.yaml"
if grep -Eiq 'test-hoodi|trust|name: POSTGRES_PASSWORD$|--slashing-protection-db-password=' "$tmp/runtime.yaml"; then printf '%s\n' 'test runtime or inline password found' >&2; exit 1; fi
conftest_bin="${CONFTEST_BIN:-conftest}"
command -v "$conftest_bin" >/dev/null 2>&1 || { printf '%s\n' 'missing command: conftest' >&2; exit 69; }
"$conftest_bin" test --policy "$root/policy/runtime" --namespace nodeoperator.runtime "$tmp/runtime.yaml" >/dev/null
printf '%s\n' 'PASS: runtime rendering requires private digests, Vault files, TLS, and retained password-auth storage.'
