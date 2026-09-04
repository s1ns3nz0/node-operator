#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
root="$(repo_root)"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

workflow="$root/.github/workflows/release.yml"
contract="$root/docs/gitops/private-release-runner-contract.md"

test -f "$workflow" || fail 'missing release workflow'
test -f "$contract" || fail 'missing private release-runner contract'

# shellcheck disable=SC2016 # The literal GitHub expression is part of the workflow contract.
grep -Fq 'runs-on: codebuild-node-operator-baseline-private-release-${{ github.run_id }}-${{ github.run_attempt }}' "$workflow" || fail 'release workflow is not bound to the dedicated CodeBuild runner and workflow-run identity'
grep -Eq '^    environment: release$' "$workflow" || fail 'release workflow does not require the protected release environment'

if grep -Fq 'runs-on: ubuntu-' "$workflow" || grep -Fq 'runs-on: windows-' "$workflow" || grep -Fq 'runs-on: macos-' "$workflow"; then
  fail 'release workflow permits a GitHub-hosted runner'
fi

# shellcheck disable=SC2016 # These are literal workflow fragments, not shell expressions.
for required in \
  'RELEASE_RUNNER_ROLE_ARN' \
  'RELEASE_ARTIFACT_BUCKET' \
  'test -n "$AWS_ROLE_ARN"; test -n "$INPUT_BUCKET"' \
  'verify-release-signature.sh'; do
  grep -Fq "$required" "$workflow" || fail "release workflow omits fail-closed prerequisite: $required"
done

printf 'PASS release workflow requires the protected private-runner boundary.\n'
