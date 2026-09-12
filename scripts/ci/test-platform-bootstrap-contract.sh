#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/release/run-platform-bootstrap.sh"
entrypoint="$root/scripts/release/interactive-hoodi-release.sh"
fail() { printf 'FAIL platform bootstrap contract: %s\n' "$*" >&2; exit 1; }

test -x "$script" || fail 'platform helper must be executable'
for required in \
  'apply-argocd-bootstrap.sh" plan' \
  'apply-vault-bootstrap.sh" plan' \
  'apply-argocd-bootstrap.sh" apply' \
  'apply-vault-bootstrap.sh" apply' \
  'aws codebuild start-build' \
  'aws codebuild batch-get-builds' \
  'vault_bootstrap_cluster_admin' \
  'all(.resource_changes[]?'; do
  grep -Fq "$required" "$script" || fail "missing control: $required"
done

grep -Fq 'run-platform-bootstrap.sh' "$entrypoint" || fail 'interactive entrypoint does not invoke platform helper'
grep -Fq 'GITHUB_TOKEN' "$script" && fail 'platform helper must not manipulate GITHUB_TOKEN'
if rg -n '(AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|VAULT_TOKEN|recovery[_-]?key|private[_-]?key)[[:space:]]*=' "$script"; then
  fail 'platform helper contains a credential assignment'
fi

printf '%s\n' 'PASS platform bootstrap plan/apply/revoke contract is present and credential-safe.'
