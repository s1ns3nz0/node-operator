#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
contract="$root/release/hoodi-release-contract.json"
template="$root/release/hoodi.ap-northeast-2.tfvars.example"
entrypoint="$root/scripts/release/node-operator-release.sh"

for file in "$contract" "$template" "$entrypoint" "$root/docs/operations/release-bootstrap.md" "$root/docs/operations/terraform-ssm-state-migration.md"; do
  [ -f "$file" ] || { printf 'missing release foundation file: %s\n' "$file" >&2; exit 1; }
done

jq -e '
  .schema_version == "v1" and .network == "hoodi" and .region == "ap-northeast-2" and
  .client_chart == {name:"node-operator-client",revision:"0.1.13"} and
  (.bootstrap.forbidden_inputs | index("validator key"))
' "$contract" >/dev/null

rg -Fx 'enable_temporary_ssm_ops_host = false' "$template" >/dev/null
rg -Fx 'enable_argocd_bootstrap_cluster_admin = false' "$template" >/dev/null
rg -Fx 'enable_vault_bootstrap_cluster_admin  = false' "$template" >/dev/null
rg -F 'SSM operations access belongs to the isolated ops-access command' "$entrypoint" >/dev/null
rg -F 'temporary cluster-admin bootstrap requires its separately approved phase' "$entrypoint" >/dev/null

if rg -n -i 'vault(_token)?[[:space:]]*=[[:space:]]*[^"[:space:]]+|private[_-]?key[[:space:]]*=[[:space:]]*[^"[:space:]]+|seed_phrase[[:space:]]*=[[:space:]]*[^"[:space:]]+|withdrawal_credential[[:space:]]*=[[:space:]]*[^"[:space:]]+' "$template" "$entrypoint"; then
  printf 'release foundation contains a prohibited credential literal\n' >&2
  exit 1
fi

printf 'PASS release bootstrap contract preserves the non-secret and separated-operations boundary.\n'
