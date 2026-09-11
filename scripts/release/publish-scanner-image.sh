#!/usr/bin/env bash
# Check objective: Publish the scanner image release.
set -euo pipefail

expected="$({ sha256sum .ci/scanners/Dockerfile .ci/scanners/Dockerfile.dockerignore .ci/scanners/run-security-scan.sh scripts/ci/collect-pr-evidence.sh scripts/ci/collect-security-evidence.sh scripts/ci/lib/common.sh; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
test "$expected" = "$(cat /tmp/scanner-image/scanner-input.sha256)"
docker load --input /tmp/scanner-image/scanner-image.tar
build_image="$IMAGE:build-${GITHUB_SHA}"
test "$expected" = "$(docker image inspect --format '{{ index .Config.Labels "io.node-operator.scanner-input-sha" }}' "$build_image")"
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker tag "$build_image" "$IMAGE:${GITHUB_SHA}"
docker tag "$build_image" "$IMAGE:main"
docker push "$IMAGE:${GITHUB_SHA}"
docker push "$IMAGE:main"
