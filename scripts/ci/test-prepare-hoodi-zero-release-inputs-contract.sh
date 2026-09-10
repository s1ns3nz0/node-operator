#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/release/prepare-hoodi-zero-release-inputs.sh"
scratch="$(mktemp -d /private/tmp/node-operator-zero-release-inputs.XXXXXX)"
output="$scratch/inputs"
key='0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
web3signer='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-web3signer@sha256:9a20e02a5821ad72fd318fa2a3ec0158a9a5acd9db80aa9214e9cc991ad4dbc3'
postgres='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-runtime-postgres@sha256:030da09481c3876b71a7e49738a932e1c18c398201a1e4ccfdbff1e5a541215b'
prysm='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-prysm@sha256:7fe554adf0efd27c0e5c5a3f80a3bbbec3d3872626208cf0a003b0dee7761f89'
fence='106760547719.dkr.ecr.ap-northeast-2.amazonaws.com/node-operator-baseline-validator-fence@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

"$script" --aws-account-id 106760547719 --backend-principal-arn arn:aws:iam::106760547719:role/NodeOperatorTerraformApply --validator-set hoodi-zero-001 --validator-public-key "$key" --withdrawal-address 0x403ff64383b8ddf994d5563550c8040d89f025ac --web3signer-image "$web3signer" --postgres-image "$postgres" --prysm-validator-image "$prysm" --signing-fence-image "$fence" --kubernetes-api-cidr 10.100.0.1/32 --output-dir "$output" >/dev/null
[ "$(stat -f '%Lp' "$output")" = 700 ]
for file in zero-resource/zero-resource-inputs.json validator-deployment/validator-deployment-handoff.json hoodi-zero-release-inputs.json; do
  [ -f "$output/$file" ] || { printf 'missing release input: %s\n' "$file" >&2; exit 1; }
  [ "$(stat -f '%Lp' "$output/$file")" = 600 ] || { printf 'unsafe release input mode: %s\n' "$file" >&2; exit 1; }
done
jq -e --arg output "$output" '.schema_version == 1 and .network == "hoodi" and .aws_account_id == "106760547719" and .validator_set == "hoodi-zero-001" and .zero_resource_inputs == ($output + "/zero-resource/zero-resource-inputs.json") and .validator_deployment_handoff == ($output + "/validator-deployment/validator-deployment-handoff.json") and (.required_checkpoints | length == 6)' "$output/hoodi-zero-release-inputs.json" >/dev/null
jq -e '.aws_account_id == "106760547719"' "$output/zero-resource/zero-resource-inputs.json" >/dev/null
jq -e '.validator_set == "hoodi-zero-001" and .staged_client_replicas == 0 and .staged_fence_replicas == 0' "$output/validator-deployment/validator-deployment-handoff.json" >/dev/null
printf '%s\n' 'PASS: one bounded command prepares the complete non-secret zero-resource and validator input set.'
