#!/usr/bin/env bash
# Check objective: Run the trusted Terraform collector offline against read-only PR input.
set -euo pipefail

echo "$REGISTRY_TOKEN" | docker login ghcr.io -u "$REGISTRY_USERNAME" --password-stdin
docker pull "$TERRAFORM_IMAGE"
mkdir -p "$RUNNER_TEMP/terraform-evidence"
docker run --rm --network none --user "$(id -u):$(id -g)" \
  --env COLLECTOR_MODE=terraform \
  --env TERRAFORM_PLUGIN_MIRROR=/opt/terraform-plugin-mirror \
  --volume "$GITHUB_WORKSPACE:/trusted:ro" \
  --volume "$GITHUB_WORKSPACE/.pr-source:/source:ro" \
  --volume "$RUNNER_TEMP/terraform-evidence:/evidence" \
  "$TERRAFORM_IMAGE" bash /trusted/scripts/ci/collect-pr-evidence.sh \
  /evidence "$SUBJECT_SHA" /source
mv "$RUNNER_TEMP/terraform-evidence/terraform.json" "$EVIDENCE_ROOT/raw/terraform.json"
