#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
schema="$root/deploy/observability/evidence-envelope.schema.json"
validator="$root/scripts/ops/validate-validator-evidence-envelope.sh"
contract="$root/docs/operations/validator-observability-contract.md"
terraform_config="$root/infra/terraform/validator-observability.tf"
for file in "$schema" "$validator" "$contract" "$terraform_config"; do test -f "$file" || { printf 'missing validator observability artifact: %s\n' "$file" >&2; exit 1; }; done
jq -e '.properties.network.const == "hoodi" and .properties.validator_public_key.pattern == "^0x[0-9a-fA-F]{96}$"' "$schema" >/dev/null
grep -Fq 'Etherscan and Beaconcha.in are asynchronous' "$contract"
grep -Fq 'forbidden field name' "$validator"
grep -Fq '!{firehose:error-output-type}' "$terraform_config"
printf 'PASS validator observability contract preserves public-only evidence boundaries.\n'
