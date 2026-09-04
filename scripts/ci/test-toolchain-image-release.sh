#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/../.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

for dockerfile in "$root/.ci/toolchains/terraform-validation.Dockerfile" "$root/.ci/toolchains/release-build.Dockerfile" "$root/.ci/toolchains/argocd-bootstrap.Dockerfile" "$root/.ci/toolchains/vault-bootstrap.Dockerfile"; do
  grep -Eqx 'FROM ubuntu@sha256:[0-9a-f]{64}' "$dockerfile"
  if grep -qE 'curl[^\n]*\|[[:space:]]*(tar|unzip|install)' "$dockerfile"; then
    printf 'toolchain image must verify downloads before extraction or installation\n' >&2
    exit 1
  fi
done

expected_input_sha="$({ sha256sum "$root/.ci/toolchains/terraform-validation.Dockerfile"; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
mkdir -p "$temporary_directory/bin"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'case "$1" in' \
  '  pull) exit 0 ;;' \
  '  image) [ "$2" = "inspect" ] && printf "%s\\n" "$EXPECTED_INPUT_SHA" ;;' \
  '  *) printf "unexpected docker command: %s\\n" "$*" >&2; exit 1 ;;' \
  'esac' > "$temporary_directory/bin/docker"
chmod +x "$temporary_directory/bin/docker"

output="$(cd "$root" && EXPECTED_INPUT_SHA="$expected_input_sha" GITHUB_REPOSITORY=s1ns3nz0/node-operator GITHUB_SHA=fixture PATH="$temporary_directory/bin:$PATH" .ci/toolchains/release-toolchain-image.sh terraform-validation .ci/toolchains/terraform-validation.Dockerfile)"
test "$output" = 'terraform-validation image inputs are unchanged; skipping build and push'

expected_bootstrap_input_sha="$({ sha256sum "$root/.ci/toolchains/argocd-bootstrap.Dockerfile" "$root/docs/gitops/argocd-private-values.example.yaml"; } | awk '{print $1}' | sha256sum | awk '{print $1}')"
output="$(cd "$root" && EXPECTED_INPUT_SHA="$expected_bootstrap_input_sha" GITHUB_REPOSITORY=s1ns3nz0/node-operator GITHUB_SHA=fixture PATH="$temporary_directory/bin:$PATH" .ci/toolchains/release-toolchain-image.sh argocd-bootstrap .ci/toolchains/argocd-bootstrap.Dockerfile docs/gitops/argocd-private-values.example.yaml)"
test "$output" = 'argocd-bootstrap image inputs are unchanged; skipping build and push'
