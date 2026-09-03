#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
require_command jq
require_command tar
require_command cmp

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

"$script_dir/build-release-bundle.sh" "$temporary_directory/first" >/dev/null
"$script_dir/build-release-bundle.sh" "$temporary_directory/second" >/dev/null

for filename in node-operator-release-bundle.tar node-operator-release-bundle.sha256 manifest.json provenance-input.json; do
  cmp "$temporary_directory/first/$filename" "$temporary_directory/second/$filename"
done

first="$temporary_directory/first"
digest="$(awk '{print $1}' "$first/node-operator-release-bundle.sha256")"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
actual="sha256:$(shasum -a 256 "$first/node-operator-release-bundle.tar" | awk '{print $1}')"
[ "$digest" = "$actual" ]

tar -tf "$first/node-operator-release-bundle.tar" | LC_ALL=C sort > "$temporary_directory/archive-paths.txt"
for required_path in \
  bundle-manifest.json \
  rendered/prysm.yaml \
  rendered/nethermind.yaml \
  source/deploy/base/namespace.yaml \
  source/deploy/prysm/kustomization.yaml \
  source/deploy/nethermind/kustomization.yaml \
  source/infra/terraform/eks.tf \
  source/policy/decision.rego; do
  rg -Fx "$required_path" "$temporary_directory/archive-paths.txt" >/dev/null
done

extract_directory="$temporary_directory/extract"
mkdir "$extract_directory"
tar -xf "$first/node-operator-release-bundle.tar" -C "$extract_directory"
rg -F 'name: prysm-hoodi-gp3-kms' "$extract_directory/rendered/prysm.yaml" >/dev/null
rg -F 'name: nethermind-hoodi-gp3-kms' "$extract_directory/rendered/nethermind.yaml" >/dev/null
cmp <(git show HEAD:deploy/prysm/kustomization.yaml) "$extract_directory/source/deploy/prysm/kustomization.yaml"
cmp <(git show HEAD:policy/decision.rego) "$extract_directory/source/policy/decision.rego"
jq -e --arg digest "$digest" '
  .schema_version == "v1" and
  .artifact.digest == $digest and
  (.entries | type == "array" and length > 10) and
  all(.entries[]; (.path | startswith("source/") or startswith("rendered/")) and (.sha256 | test("^[0-9a-f]{64}$")))
' "$first/manifest.json" >/dev/null
jq -e --arg digest "$digest" '
  .subject == [{name:"node-operator-release-bundle.tar",digest:{sha256:($digest | ltrimstr("sha256:"))}}] and
  .predicate.buildDefinition.buildType == "https://node-operator.example/release-bundle/v1" and
  .predicate.runDetails.builder.id == "local://node-operator/scripts/ci/build-release-bundle.sh"
' "$first/provenance-input.json" >/dev/null
jq -e --arg digest "$digest" '
  .bomFormat == "CycloneDX" and
  (.components | type == "array") and
  .metadata.component.name == "node-operator-release-bundle.tar" and
  .metadata.component.version == $digest and
  (.metadata.tools.components | any(.[]; .name == "syft"))
' "$first/sbom.cyclonedx.json" >/dev/null

if rg -n 'DO_NOT_PERSIST_|-----BEGIN( [A-Z]+)? PRIVATE KEY-----|(^|[[:space:]])kind:[[:space:]]*Secret([[:space:]]|$)' "$extract_directory" "$first/manifest.json" "$first/provenance-input.json" "$first/sbom.cyclonedx.json" >/dev/null; then
  printf 'bundle contains raw fixture or sensitive material\n' >&2
  exit 1
fi
