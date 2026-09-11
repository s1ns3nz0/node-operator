#!/usr/bin/env bash
# Check objective: Download only this run's completed verification artifacts.
set -euo pipefail

bash scripts/ci/verify-release-source-eligibility.sh "$GITHUB_SHA"
for component in server agent injector; do
  gh run download "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" \
    --name "vault-runtime-$component-verification" \
    --dir "$RUNNER_TEMP/vault-signed-evidence/vault-runtime-$component-verification"
done
