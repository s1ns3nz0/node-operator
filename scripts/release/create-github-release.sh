#!/usr/bin/env bash
# Check objective: Publish exactly the reviewed release bundle and signer verification assets.
set -euo pipefail
tag="${GITHUB_REF_NAME}"
gh release create "$tag" \
  "$RUNNER_TEMP/release/node-operator-release-bundle.tar" \
  "$RUNNER_TEMP/release/node-operator-release-bundle.sha256" \
  "$RUNNER_TEMP/release/manifest.json" \
  "$RUNNER_TEMP/release/sbom.cyclonedx.json" \
  "$RUNNER_TEMP/release/provenance-input.json" \
  "$RUNNER_TEMP/release/signer-output/release-verification.json" \
  --title "$tag" --generate-notes
