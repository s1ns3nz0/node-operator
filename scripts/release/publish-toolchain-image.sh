#!/usr/bin/env bash
# Check objective: Publish the toolchain image release.
# Purpose: Verify a staged toolchain image's inputs and publish immutable and main tags.
# Inputs: DOCKERFILE, IMAGE, GITHUB_SHA, REGISTRY_TOKEN, REGISTRY_USERNAME, staged files under /tmp/toolchain-image, and optional INPUT_FILE.
# Outputs: Published GHCR image tags; no structured workflow output.
# Side effects: Loads a Docker image, authenticates to GHCR, and pushes two tags.
set -euo pipefail

expected="$({ sha256sum "$DOCKERFILE" ${INPUT_FILE:+"$INPUT_FILE"}; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
test "$expected" = "$(cat /tmp/toolchain-image/toolchain-input.sha256)"
docker load --input /tmp/toolchain-image/toolchain-image.tar
build_image="$IMAGE:build-${GITHUB_SHA}"
test "$expected" = "$(docker image inspect --format '{{ index .Config.Labels "io.node-operator.toolchain-input-sha" }}' "$build_image")"
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker tag "$build_image" "$IMAGE:${GITHUB_SHA}"
docker tag "$build_image" "$IMAGE:main"
docker push "$IMAGE:${GITHUB_SHA}"
docker push "$IMAGE:main"
