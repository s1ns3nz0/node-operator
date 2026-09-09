#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
dockerfile="$root/.ci/prysm-beacon-runtime/Dockerfile"; lock="$root/.ci/prysm-beacon-runtime/source.lock.json"
for file in "$dockerfile" "$lock"; do test -f "$file" || { echo "missing: $file" >&2; exit 1; }; done
jq -e '.commit == "51b5a75ebbadf05af22bd2601b5baf7a9e99b66d" and .target == "./cmd/beacon-chain" and .security_patch_sha256 == "6b3b1a3a904ab4ccd6b0a13a859e07b2c0c3b859dcfd4368d31b30408c45f3b8"' "$lock" >/dev/null
grep -Fq '51b5a75ebbadf05af22bd2601b5baf7a9e99b66d' "$dockerfile"
grep -Fq 'go test -mod=readonly -count=1 ./cmd/beacon-chain/flags ./cmd/beacon-chain/jwt ./beacon-chain/core/blocks' "$dockerfile"
grep -Fq 'go list -mod=readonly -deps ./cmd/beacon-chain' "$dockerfile"
grep -Fq 'go version -m /out/beacon-chain' "$dockerfile"
grep -Fq 'USER 1000:1000' "$dockerfile"
printf '%s\n' 'PASS: Beacon runtime contract pins source, dependency patch, core/config tests, and dependency inventory.'
