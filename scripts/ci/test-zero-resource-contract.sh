#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
contract="$root/infra/baseline/variables.tf"
network="$root/infra/foundation-network/main.tf"
test -f "$contract"
rg -F 'variable "foundation_network"' "$contract" >/dev/null
rg -F 'system_subnet_ids' "$contract" >/dev/null
rg -F 'hoodi_subnet_ids' "$contract" >/dev/null
rg -F 'aws_nat_gateway' "$network" >/dev/null
if rg -n 'variable "hoodi_nat_gateway_id"' "$root/infra/baseline"; then
  printf 'replacement baseline must not accept an external NAT gateway\n' >&2
  exit 1
fi
printf 'PASS zero-resource foundation and replacement-baseline boundary.\n'
