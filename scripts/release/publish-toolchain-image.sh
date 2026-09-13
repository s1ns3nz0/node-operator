#!/usr/bin/env bash
# Check objective: Publish the toolchain image release.
# Purpose: Verify a staged toolchain image's inputs and publish immutable and main tags.
# Inputs: DOCKERFILE, IMAGE, IMAGE_NAME, GITHUB_SHA, REGISTRY_TOKEN, REGISTRY_USERNAME, staged files under TOOLCHAIN_IMAGE_DIR, and optional INPUT_FILE.
# Outputs: Signed GHCR image/SBOM and verification evidence.
# Side effects: Loads and pushes an image; promotes main only after signature verification.
set -euo pipefail
test "${GITHUB_REF:-}" = refs/heads/main
test "${GITHUB_REPOSITORY:-}" = s1ns3nz0/node-operator
[[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
case "${IMAGE_NAME:-}" in
  terraform-validation|release-build|vault-release-signer|gitops-oci-mirror|argocd-bootstrap|vault-bootstrap) ;;
  *) printf '%s\n' 'unapproved toolchain repository' >&2; exit 65 ;;
esac
test "${IMAGE:-}" = "ghcr.io/s1ns3nz0/node-operator/$IMAGE_NAME"
: "${RUNNER_TEMP:?RUNNER_TEMP is required for signing evidence}"
command -v cosign >/dev/null

expected="$({ sha256sum "$DOCKERFILE" ${INPUT_FILE:+"$INPUT_FILE"}; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
staged_dir="${TOOLCHAIN_IMAGE_DIR:-/tmp/toolchain-image}"
test "$expected" = "$(cat "$staged_dir/toolchain-input.sha256")"
docker load --input "$staged_dir/toolchain-image.tar"
build_image="$IMAGE:build-${GITHUB_SHA}"
test "$expected" = "$(docker image inspect --format '{{ index .Config.Labels "io.node-operator.toolchain-input-sha" }}' "$build_image")"
local_config_digest="$(docker image inspect --format '{{.Id}}' "$build_image")"
[[ "$local_config_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { printf '%s\n' 'local toolchain image config digest is invalid' >&2; exit 65; }
python3 scripts/ci/image_sbom_evidence.py verify \
  --archive "$staged_dir/toolchain-image.tar" --sbom "$staged_dir/toolchain-sbom/sbom.cyclonedx.json" \
  --receipt "$staged_dir/toolchain-sbom/receipt.json" --subject "$IMAGE_NAME" --revision "$GITHUB_SHA" \
  --image-config-digest "$local_config_digest"
# Unification rejects a defined false decision before registry authentication.
opa eval --fail --format pretty --data policy/image_sbom.rego \
  --input "$staged_dir/toolchain-sbom/receipt.json" 'true = data.nodeoperator.image_sbom.allow'
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker tag "$build_image" "$IMAGE:${GITHUB_SHA}"
docker push "$IMAGE:${GITHUB_SHA}"
bash scripts/release/sign-ci-image-evidence.sh "$IMAGE" "$local_config_digest" \
  "$staged_dir/toolchain-sbom/sbom.cyclonedx.json" "$staged_dir/toolchain-sbom/receipt.json" \
  "${RUNNER_TEMP:?}/toolchain-signing-evidence/$IMAGE_NAME"
docker tag "$build_image" "$IMAGE:main"
docker push "$IMAGE:main"
