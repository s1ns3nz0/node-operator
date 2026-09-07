#!/usr/bin/env bash
set -euo pipefail

# Read-only, fail-closed verification of the post-initialization Vault audit
# ceremony. VAULT_TOKEN is supplied by the approved operator environment and
# is never read from arguments or printed by this script.
for command in vault jq; do
  command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }
done
: "${VAULT_ADDR:?VAULT_ADDR must target the private Vault endpoint}"
: "${VAULT_TOKEN:?VAULT_TOKEN must be supplied by the approved Vault administrator environment}"

audit_devices="$(vault audit list -format=json)"
jq -e '
  .["validator-file/"]?.type == "file" and
  .["validator-socket/"]?.type == "socket" and
  .["validator-file/"].options.log_raw != "true" and
  .["validator-socket/"].options.log_raw != "true" and
  .["validator-file/"].options.elide_list_responses == "true" and
  .["validator-socket/"].options.elide_list_responses == "true" and
  .["validator-file/"].options.file_path == "/vault/audit/validator-audit.json" and
  .["validator-socket/"].options.address == "unix:///vault/audit/validator-audit.sock"
' <<<"$audit_devices" >/dev/null || {
  printf 'FAIL: required Vault validator audit devices/options are missing or unsafe; do not enable validator duties.\n' >&2
  exit 65
}
printf 'PASS: Vault file and local-socket audit devices are configured with raw logging disabled.\n'
