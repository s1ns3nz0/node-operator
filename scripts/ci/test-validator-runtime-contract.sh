#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
renderer="$root/scripts/ops/render-hoodi-validator-runtime.sh"
tmp="$(mktemp -d /private/tmp/node-operator-runtime-render.XXXXXX)"
web3signer='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-web3signer@sha256:4a76635561a7877bf694b81ff1707c118dff6ea48f47c5d1c514e91e637db51a'
postgres='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-postgres@sha256:030da09481c3876b71a7e49738a932e1c18c398201a1e4ccfdbff1e5a541215b'
"$renderer" --validator-set hoodi-test-001 --web3signer-image "$web3signer" --postgres-image "$postgres" --output "$tmp/runtime.yaml" >/dev/null
grep -Fq 'POSTGRES_PASSWORD_FILE' "$tmp/runtime.yaml"
grep -Fq 'persistentVolumeClaimRetentionPolicy:' "$tmp/runtime.yaml"
grep -Fq 'name: PGDATA, value: /var/lib/postgresql/data/pgdata' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-db-dependencies' "$tmp/runtime.yaml"
grep -Fq 'readOnlyRootFilesystem: true' "$tmp/runtime.yaml"
grep -Fq 'limits: {cpu: "2", memory: 4Gi}' "$tmp/runtime.yaml"
grep -Fq -- '--tls-keystore-file=/vault/secrets/tls.p12' "$tmp/runtime.yaml"
grep -Fq 'vault.hashicorp.com/agent-inject-secret-keystore.json' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-remote-signer' "$tmp/runtime.yaml"
grep -Fq 'validator-hoodi-test-001-primary' "$tmp/runtime.yaml"
grep -Fq 'node-operator.io/validator-set: hoodi-test-001' "$tmp/runtime.yaml"
if grep -Eiq 'test-hoodi|trust|name: POSTGRES_PASSWORD$|--slashing-protection-db-password=' "$tmp/runtime.yaml"; then printf '%s\n' 'test runtime or inline password found' >&2; exit 1; fi
conftest_bin="${CONFTEST_BIN:-conftest}"
command -v "$conftest_bin" >/dev/null 2>&1 || { printf '%s\n' 'missing command: conftest' >&2; exit 69; }
"$conftest_bin" test --policy "$root/policy/runtime" --namespace nodeoperator.runtime "$tmp/runtime.yaml" >/dev/null
printf '%s\n' 'PASS: runtime rendering requires private digests, Vault files, TLS, and retained password-auth storage.'
