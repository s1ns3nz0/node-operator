#!/usr/bin/env bash
# Check objective: Mirror approved image to private ECR.
set -euo pipefail

test -n "$ACCOUNT_ID"
destination_repository='node-operator-baseline-vault-release-signer'
destination_registry="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
immutable_tag="approved-${SOURCE_DIGEST#sha256:}"
echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$SOURCE"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$destination_registry"
docker tag "$SOURCE" "$destination_registry/$destination_repository:$immutable_tag"
docker push "$destination_registry/$destination_repository:$immutable_tag"
destination_digest="$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$destination_repository" --image-ids "imageTag=$immutable_tag" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$destination_digest" =~ ^sha256:[a-f0-9]{64}$ ]]
printf 'ecr_image=%s/%s@%s\n' "$destination_registry" "$destination_repository" "$destination_digest" >> "$GITHUB_OUTPUT"
# shellcheck disable=SC2016 # Backticks delimit Markdown code, not shell commands.
printf '### Private signer image mirror\n\n- Source: `%s`\n- Destination digest: `%s`\n' "$SOURCE" "$destination_digest" >> "$GITHUB_STEP_SUMMARY"
