#!/usr/bin/env bash
set -euo pipefail

contract="${1:-}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
source="$(jq -er .source "$contract")"
repository='node-operator-baseline-dast-zap-baseline'
tag="approved-${source##*@sha256:}"
registry="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
docker buildx imagetools create --tag "$registry/$repository:$tag" "$source"
digest="$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$repository" --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
printf 'private_image=%s/%s@%s\n' "$registry" "$repository" "$digest" >> "$GITHUB_STEP_SUMMARY"
