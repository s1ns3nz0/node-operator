#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
dockerfile="$root/.ci/validator-signing-fence/Dockerfile"
workflow="$root/.github/workflows/validator-signing-fence-image.yml"
fail(){ printf 'FAIL signing fence image contract: %s\n' "$*" >&2; exit 1; }
grep -Eq '^FROM golang:1\.26\.6-alpine@sha256:[a-f0-9]{64} AS build$' "$dockerfile" || fail 'builder is not digest pinned'
grep -Fq 'FROM scratch' "$dockerfile" || fail 'runtime is not scratch'
grep -Fq 'USER 65532:65532' "$dockerfile" || fail 'runtime is not non-root'
grep -Fq 'COPY cmd/validator-signing-fence/main.go' "$dockerfile" || fail 'reviewed source is not explicit'
grep -Fq 'environment: validator-client-ecr-mirror' "$workflow" || fail 'protected environment missing'
# Literal workflow source.
# shellcheck disable=SC2016
grep -Fq 'test "$GITHUB_REF" = refs/heads/main' "$workflow" || fail 'main-only publish gate missing'
grep -Fq 'CGO_ENABLED=0 go test ./cmd/validator-signing-fence &&' "$dockerfile" || fail 'tests do not run before the build in the digest-pinned builder'
# shellcheck disable=SC2016 # Literal workflow source.
grep -Fq 'file://$token_file' "$workflow" || fail 'OIDC token is passed in process argv instead of an indirection file'
# shellcheck disable=SC2016 # Literal workflow source.
if grep -Fq -- '--web-identity-token "$token"' "$workflow"; then fail 'OIDC token appears directly in process argv'; fi
grep -Fq '::add-mask::' "$workflow" || fail 'temporary credentials are not masked'
grep -Fq 'persist-credentials: false' "$workflow" || fail 'checkout credentials persist'
grep -Fq 'repository=node-operator-baseline-validator-fence' "$workflow" || fail 'fence image is not type-separated from Prysm'
grep -Fq 'install-validator-signing-fence-release-tools.sh' "$workflow" || fail 'pinned release tools are not installed'
# shellcheck disable=SC2016 # Literal workflow source.
grep -Fq 'cosign sign --yes "$subject"' "$workflow" || fail 'exact image digest is not signed'
for kind in slsaprovenance1 cyclonedx vuln; do grep -Fq "cosign attest --yes --type $kind" "$workflow" || fail "$kind attestation missing"; done
# shellcheck disable=SC2016 # Literal workflow source.
grep -Fq 'collect-validator-signing-fence-release-evidence.sh "$subject" "$GITHUB_SHA"' "$workflow" || fail 'authenticated release collector is not executed'
grep -Fq 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' "$workflow" || fail 'sanitized release evidence is not retained through a pinned action'
grep -Fq 'aws_ecr_repository" "validator_signing_fence' "$root/infra/terraform/validator-client-ecr-mirror.tf" || fail 'dedicated immutable fence repository missing'
if grep -Eq 'ecr:(Delete|SetRepositoryPolicy)|docker build .*--push' "$workflow"; then fail 'destructive or unreviewed publish path found'; fi
printf '%s\n' 'PASS signing fence image is review-built from pinned inputs through the protected OIDC environment.'
