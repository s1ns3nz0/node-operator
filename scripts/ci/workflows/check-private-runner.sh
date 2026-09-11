#!/usr/bin/env bash
# Check objective: Verify the ephemeral runner and pinned build image without releasing artifacts.
# Purpose: Prove the private CodeBuild runner can authenticate and pull the pinned release-build image.
# Inputs: CODEBUILD_BUILD_ID, GITHUB_RUN_ID, registry credentials, and RELEASE_BUILD_IMAGE.
# Outputs: Exit status only.
# Side effects: Read-only Docker daemon and GHCR login/pull; no artifact publication.
set -euo pipefail

set -eu
test -n "$CODEBUILD_BUILD_ID"
test -n "$GITHUB_RUN_ID"
docker version --format '{{.Server.Version}}' >/dev/null
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$RELEASE_BUILD_IMAGE" >/dev/null
