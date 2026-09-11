#!/usr/bin/env bash
# Check objective: Build the approved release bundle and bind its SBOM to the reproducibility digest.
set -euo pipefail
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$RELEASE_BUILD_IMAGE"
mkdir -p "$RUNNER_TEMP/release"
docker run --rm --user "$(id -u):$(id -g)" --volume "$GITHUB_WORKSPACE:/workspace:ro" --volume "$RUNNER_TEMP:/output" --workdir /workspace "$RELEASE_BUILD_IMAGE" bash scripts/ci/build-release-bundle.sh /output/release
actual_artifact_digest="sha256:$(sha256sum "$RUNNER_TEMP/release/node-operator-release-bundle.tar" | awk '{print $1}')"
test "$actual_artifact_digest" = "$APPROVED_ARTIFACT_DIGEST"
test "$(jq -er '.metadata.component.version' "$RUNNER_TEMP/release/sbom.cyclonedx.json")" = "$APPROVED_ARTIFACT_DIGEST"
