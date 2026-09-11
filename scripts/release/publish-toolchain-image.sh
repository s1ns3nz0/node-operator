#!/usr/bin/env bash
# Check objective: Publish the toolchain image release.
# Purpose: Verify a staged toolchain image's inputs and publish immutable and main tags.
# Inputs: DOCKERFILE, IMAGE, GITHUB_SHA, REGISTRY_TOKEN, REGISTRY_USERNAME, staged files under /tmp/toolchain-image, and optional INPUT_FILE.
# Outputs: Published GHCR image tags and an immutable publication record.
# Side effects: Loads a Docker image, authenticates to GHCR, and pushes two tags.
set -euo pipefail
umask 077
artifact_dir="${TOOLCHAIN_ARTIFACT_DIR:-/tmp/toolchain-image}"
if [ -n "${PUBLICATION_RECORD_OUTPUT:-}" ]; then
  record_output="$PUBLICATION_RECORD_OUTPUT"
else
  records_dir="${RUNNER_TEMP:?RUNNER_TEMP or PUBLICATION_RECORD_OUTPUT is required}/toolchain-publication-records"
  mkdir -m 700 "$records_dir" 2>/dev/null || true
  record_output="$records_dir/toolchain-${IMAGE_NAME:?IMAGE_NAME is required}-publication-record.json"
fi
case "$record_output" in /*) ;; *) printf '%s\n' 'publication record output must be absolute' >&2; exit 64 ;; esac
record_parent="$(dirname "$record_output")"
[ -d "$record_parent" ] && [ ! -L "$record_parent" ] && [ ! -e "$record_output" ] && [ ! -L "$record_output" ] || { printf '%s\n' 'publication record path is unsafe' >&2; exit 65; }
record_parent_mode="$(stat -c '%a' "$record_parent" 2>/dev/null || stat -f '%OLp' "$record_parent")"
[ "$record_parent_mode" = 700 ] || { printf '%s\n' 'publication record parent must be private' >&2; exit 65; }
[[ "${GITHUB_SHA:?GITHUB_SHA is required}" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'GITHUB_SHA must be a lowercase commit SHA' >&2; exit 64; }
[[ "${GITHUB_WORKFLOW:?GITHUB_WORKFLOW is required}" != '' ]] && [[ "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}" =~ ^[0-9]+$ ]] && [[ "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}" =~ ^[0-9]+$ ]] || { printf '%s\n' 'GitHub publication context is invalid' >&2; exit 64; }

# Use the same ordered input list as the unprivileged build job.
input_files=("$DOCKERFILE")
if [ -n "${INPUT_FILE:-}" ]; then
  read -r -a extra_inputs <<< "$INPUT_FILE"
  input_files+=("${extra_inputs[@]}")
fi
expected="$({ sha256sum "${input_files[@]}"; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
[[ "$expected" =~ ^[a-f0-9]{64}$ ]] || { printf '%s\n' 'toolchain input hash is invalid' >&2; exit 65; }
test "$expected" = "$(cat "$artifact_dir/toolchain-input.sha256")"
docker load --input "$artifact_dir/toolchain-image.tar"
build_image="$IMAGE:build-${GITHUB_SHA}"
test "$expected" = "$(docker image inspect --format '{{ index .Config.Labels "io.node-operator.toolchain-input-sha" }}' "$build_image")"
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker tag "$build_image" "$IMAGE:${GITHUB_SHA}"
docker tag "$build_image" "$IMAGE:main"
docker push "$IMAGE:${GITHUB_SHA}"
docker push "$IMAGE:main"
manifest_digest="$(docker buildx imagetools inspect "$IMAGE:${GITHUB_SHA}" --format '{{.Digest}}')"
[[ "$manifest_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { printf '%s\n' 'registry did not return an immutable manifest digest for the exact release tag' >&2; exit 65; }
stage="$(mktemp "$record_parent/.toolchain-publication-record.XXXXXX")"
trap 'rm -f "$stage"' EXIT
jq -n --arg component "$IMAGE_NAME" --arg revision "$GITHUB_SHA" --arg image_ref "$IMAGE@$manifest_digest" --arg digest "$manifest_digest" --arg input_sha "$expected" --arg workflow "${GITHUB_WORKFLOW:?GITHUB_WORKFLOW is required}" --arg run_id "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}" --arg invocation "github-actions:${GITHUB_RUN_ID}:${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}" \
  '{schema_version:1,component:$component,kind:"image",release_revision:$revision,build_revision:$revision,third_party_source_revision:null,image_ref:$image_ref,manifest_digest:$digest,input_sha256:$input_sha,publication:{workflow:$workflow,run_id:$run_id,invocation:$invocation},verification:{method:"input-hash-and-registry-digest",status:"passed"}}' > "$stage"
chmod 600 "$stage"
ln "$stage" "$record_output" || { printf '%s\n' 'refusing to overwrite publication record' >&2; exit 65; }
rm -f "$stage"
trap - EXIT
