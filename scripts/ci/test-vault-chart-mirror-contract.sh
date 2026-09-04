#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
allowlist="$root/.ci/gitops/approved-oci-artifacts.json"
workflow="$root/.github/workflows/vault-chart-mirror.yml"

jq -e '
  .version == 1 and
  (.helm_archives | type == "array") and
  ([.helm_archives[] | select(.name == "vault")] | length == 1) and
  (.helm_archives[] | select(.name == "vault") |
    .version == "0.31.0" and
    .source == "https://helm.releases.hashicorp.com/vault-0.31.0.tgz" and
    (.sha256 | test("^[a-f0-9]{64}$")) and
    .destination == "vault" and .ecrTag == "0.31.0")
' "$allowlist" >/dev/null

for required in \
  '.helm_archives[] | select(.name == "vault")' \
  'chart_source' \
  'chart_sha256' \
  'chart_destination' \
  'test "$chart_destination" = vault' \
  'sha256sum --check --status' \
  'helm push "$RUNNER_TEMP/vault-$chart_version.tgz"'; do
  grep -Fq "$required" "$workflow"
done

if grep -Fq "helm pull vault --repo" "$workflow"; then
  printf 'Vault chart mirror must not bypass the approved archive record.\n' >&2
  exit 1
fi

printf 'PASS Vault chart mirror is bound to the approved archive record.\n'
