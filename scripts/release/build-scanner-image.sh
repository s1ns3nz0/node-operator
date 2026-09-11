#!/usr/bin/env bash
# Check objective: Build the scanner image release.
set -euo pipefail

input_sha="$({ sha256sum .ci/scanners/Dockerfile .ci/scanners/Dockerfile.dockerignore .ci/scanners/run-security-scan.sh scripts/ci/collect-pr-evidence.sh scripts/ci/collect-security-evidence.sh scripts/ci/lib/common.sh; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
docker build --build-arg "SCANNER_INPUT_SHA=$input_sha" --file .ci/scanners/Dockerfile --tag "$IMAGE:build-${GITHUB_SHA}" .
docker save --output scanner-image.tar "$IMAGE:build-${GITHUB_SHA}"
printf '%s\n' "$input_sha" > scanner-input.sha256
echo 'changed=true' >> "$GITHUB_OUTPUT"
