#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
renderer="$root/scripts/ops/render-hoodi-validator-client.sh"
tmp="$(mktemp -d /private/tmp/node-operator-client-render.XXXXXX)"
image='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-prysm@sha256:7fe554adf0efd27c0e5c5a3f80a3bbbec3d3872626208cf0a003b0dee7761f89'
native_image='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-prysm@sha256:8a1d48b8fddaf6a16d151743624e854bd8cf44267b41e97de53aa2506cd1494f'
fence_image='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-fence@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
key='0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
allowlist="$root/.ci/validator/approved-client-images.json"
jq -e '.schema_version == 2 and all(.images[]; (.private_image | test("^106760547719\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/node-operator-baseline-validator-prysm@sha256:[a-f0-9]{64}$")) and (.release_channel == "upstream-mirror" or .release_channel == "manual-native-mtls") and (.stage_approved | type == "boolean") and (.activation_approved | type == "boolean"))' "$allowlist" >/dev/null
if jq 'del(.images[1].release_channel)' "$allowlist" | jq -e --arg image "$native_image" '.schema_version == 2 and any(.images[]; .private_image == $image and .stage_approved == true and (.release_channel == "upstream-mirror" or .release_channel == "manual-native-mtls"))' >/dev/null; then
  printf '%s\n' 'missing release channel unexpectedly passes stage contract' >&2; exit 1
fi
"$renderer" --validator-set hoodi-test-001 --validator-public-key "$key" --prysm-validator-image "$image" --signing-fence-image "$fence_image" --kubernetes-api-cidr 10.100.0.1/32 --output "$tmp/client.yaml" >/dev/null
"$renderer" --validator-set hoodi-test-001 --validator-public-key "$key" --prysm-validator-image "$native_image" --signing-fence-image "$fence_image" --kubernetes-api-cidr 10.100.0.1/32 --output "$tmp/native-client.yaml" >/dev/null
for rejected in \
  "106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/other-repository@${native_image##*@}" \
  "106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-prysm@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"; do
  if "$renderer" --validator-set hoodi-test-001 --validator-public-key "$key" --prysm-validator-image "$rejected" --signing-fence-image "$fence_image" --kubernetes-api-cidr 10.100.0.1/32 --output "$tmp/rejected-client.yaml" >/dev/null 2>&1; then
    printf 'unexpectedly rendered unapproved client image: %s\n' "$rejected" >&2; exit 1
  fi
done
grep -Fq 'replicas: 0' "$tmp/client.yaml"
grep -Fq -- '--validators-external-signer-url=https://' "$tmp/client.yaml"
grep -Fq -- '--datadir=/data' "$tmp/client.yaml"
if grep -Fq -- '--remote-signer-ca-crt-path=' "$tmp/client.yaml"; then printf '%s\n' 'gRPC-only CA flag must not stand in for Web3Signer HTTP trust' >&2; exit 1; fi
grep -Fq -- '--validators-external-signer-http-client-cert=/etc/remote-signer/tls.crt' "$tmp/client.yaml"
grep -Fq -- '--validators-external-signer-http-client-key=/etc/remote-signer/tls.key' "$tmp/client.yaml"
grep -Fq -- '--validators-external-signer-http-ca-cert=/etc/remote-signer/ca.crt' "$tmp/client.yaml"
grep -Fq 'automountServiceAccountToken: false' "$tmp/client.yaml"
grep -Fq 'secretName: validator-hoodi-test-001-client-tls' "$tmp/client.yaml"
grep -Fq 'defaultMode: 0440' "$tmp/client.yaml"
grep -Fq 'fsGroup: 1000' "$tmp/client.yaml"
if grep -Eq 'SSL_CERT_FILE|binaryData:|vault.hashicorp.com' "$tmp/client.yaml"; then printf '%s\n' 'client received ambient trust or Vault configuration' >&2; exit 1; fi
grep -Fq 'name: validator-hoodi-test-001-signing-fence' "$tmp/client.yaml"
grep -Fq 'replicas: 0' "$tmp/client.yaml"
grep -Fq '10.100.0.1/32' "$tmp/client.yaml"
grep -Fq 'serviceAccountName: validator-hoodi-test-001-client-fence' "$tmp/client.yaml"
grep -Fq 'expirationSeconds: 600' "$tmp/client.yaml"
grep -Fq 'fsGroup: 65532' "$tmp/client.yaml"
grep -Fq 'defaultMode: 0440' "$tmp/client.yaml"
grep -Fq 'httpGet: {path: /healthz, port: health}' "$tmp/client.yaml"
ruby -ryaml -e 'documents=YAML.load_stream(File.read(ARGV[0])); client=documents.find{|d| d.is_a?(Hash) && d["kind"]=="StatefulSet" && d.dig("metadata","name")=="validator-hoodi-test-001-client"}; abort "client missing" unless client; abort "client identity is not stable" unless client.dig("spec","serviceName")=="validator-hoodi-test-001-client-headless"; mounts=client.dig("spec","template","spec","containers").flat_map{|c| c["volumeMounts"] || []}; abort "client received fence token" if mounts.any?{|m| m["name"]=="api-token"}' "$tmp/client.yaml"
grep -Fq 'resourceNames: ["validator-hoodi-test-001-client-0"]' "$tmp/client.yaml"
printf '%s\n' 'PASS: validator client uses set-scoped HTTP mTLS files and cannot start before activation.'
