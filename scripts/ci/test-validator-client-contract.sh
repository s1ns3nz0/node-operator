#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
renderer="$root/scripts/ops/render-hoodi-validator-client.sh"
tmp="$(mktemp -d /private/tmp/node-operator-client-render.XXXXXX)"
image='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-prysm@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
key='0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
printf '%s\n%s\n' '-----BEGIN CERTIFICATE-----' '-----END CERTIFICATE-----' > "$tmp/ca.crt"
"$renderer" --validator-set hoodi-test-001 --validator-public-key "$key" --prysm-validator-image "$image" --signer-ca "$tmp/ca.crt" --output "$tmp/client.yaml" >/dev/null
grep -Fq 'replicas: 0' "$tmp/client.yaml"
grep -Fq -- '--validators-external-signer-url=https://' "$tmp/client.yaml"
grep -Fq -- '--remote-signer-ca-crt-path=/etc/remote-signer/ca.crt' "$tmp/client.yaml"
grep -Fq 'automountServiceAccountToken: false' "$tmp/client.yaml"
grep -Fq 'binaryData:' "$tmp/client.yaml"
printf '%s\n' 'PASS: validator client is TLS-pinned and cannot start before activation.'
