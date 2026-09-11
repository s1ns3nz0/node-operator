#!/usr/bin/env bash
# Check objective: Build the toolchain image release.
# Purpose: Build a reviewed toolchain image and stage it for publishing.
# Inputs: DOCKERFILE, IMAGE, IMAGE_NAME, GITHUB_SHA, GITHUB_WORKSPACE, and optional INPUT_FILE.
# Outputs: toolchain-image.tar and toolchain-input.sha256 in the working directory.
# Side effects: Builds and saves a local Docker image; release-build also runs its bundle contract.
set -euo pipefail

# Matrix inputs are space-delimited repository paths; arrays prevent glob expansion.
input_files=("$DOCKERFILE")
if [ -n "${INPUT_FILE:-}" ]; then
  read -r -a extra_inputs <<< "$INPUT_FILE"
  input_files+=("${extra_inputs[@]}")
fi
input_sha="$({ sha256sum "${input_files[@]}"; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
docker build --build-arg "TOOLCHAIN_INPUT_SHA=$input_sha" --file "$DOCKERFILE" --tag "$IMAGE:build-${GITHUB_SHA}" .
# A Dockerfile build alone cannot prove that its declared commands
# satisfy the release bundle contract. Exercise the newly built,
# un-published release image against the checked-out PR source.
if [ "$IMAGE_NAME" = release-build ]; then
  docker run --rm --user "$(id -u):$(id -g)" --volume "$GITHUB_WORKSPACE:/workspace:ro" --workdir /workspace "$IMAGE:build-${GITHUB_SHA}" bash scripts/ci/test-build-release-bundle.sh
fi
docker save --output toolchain-image.tar "$IMAGE:build-${GITHUB_SHA}"
printf '%s\n' "$input_sha" > toolchain-input.sha256
