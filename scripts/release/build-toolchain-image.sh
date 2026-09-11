#!/usr/bin/env bash
# Check objective: Build the toolchain image release.
set -euo pipefail

input_sha="$({ sha256sum "$DOCKERFILE" ${INPUT_FILE:+"$INPUT_FILE"}; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
docker build --build-arg "TOOLCHAIN_INPUT_SHA=$input_sha" --file "$DOCKERFILE" --tag "$IMAGE:build-${GITHUB_SHA}" .
# A Dockerfile build alone cannot prove that its declared commands
# satisfy the release bundle contract. Exercise the newly built,
# un-published release image against the checked-out PR source.
if [ "$IMAGE_NAME" = release-build ]; then
  docker run --rm --user "$(id -u):$(id -g)" --volume "$GITHUB_WORKSPACE:/workspace:ro" --workdir /workspace "$IMAGE:build-${GITHUB_SHA}" bash scripts/ci/test-build-release-bundle.sh
fi
docker save --output toolchain-image.tar "$IMAGE:build-${GITHUB_SHA}"
printf '%s\n' "$input_sha" > toolchain-input.sha256
