#!/usr/bin/env bash
set -euo pipefail

# Build the node-operator release artifact without contacting a registry or a
# cluster.  The artifact is an uncompressed, deterministic POSIX tar archive:
# its entries have fixed ownership, permissions, and modification time.
#
# The bundle deliberately contains only deployable/rendered manifests and
# policy/IaC source needed to review them.  Fixtures, raw scanner evidence,
# credentials, and release-tool reports are outside this boundary.

if [ "$#" -ne 1 ]; then
  printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"

output_directory="$1"
root="$(repo_root)"
require_command kubectl
require_command node
require_command shasum
require_command syft
require_command jq

source_revision="$(git -C "$root" rev-parse HEAD)"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { printf 'unable to determine source revision\n' >&2; exit 1; }

umask 077
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
stage_directory="$temporary_directory/stage"
mkdir -p "$stage_directory/source" "$stage_directory/rendered"

path_is_in_release_boundary() {
  case "$1" in
    deploy/base/*.yaml|deploy/prysm/*.yaml|deploy/nethermind/*.yaml|infra/terraform/*.tf|infra/terraform/terraform.tfvars.example|policy/data/*.rego|policy/data/*.json|policy/runtime/*.rego|policy/terraform/*.rego|policy/prysm/*.rego|policy/nethermind/hardening.rego|policy/schemas/*.json|policy/*.rego)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

materialize_source_file() {
  local relative_path="$1"
  mkdir -p "$stage_directory/source/$(dirname "$relative_path")"
  git -C "$root" show "$source_revision:$relative_path" > "$stage_directory/source/$relative_path"
}

while IFS= read -r relative_path; do
  path_is_in_release_boundary "$relative_path" && materialize_source_file "$relative_path"
done < <(git -C "$root" ls-tree -r --name-only "$source_revision" | LC_ALL=C sort)

kubectl kustomize "$stage_directory/source/deploy/prysm" > "$stage_directory/rendered/prysm.yaml"
kubectl kustomize "$stage_directory/source/deploy/nethermind" > "$stage_directory/rendered/nethermind.yaml"

# Kubernetes Secret objects and common private-key encodings do not belong in
# a distributable release bundle.  This is a boundary check, not a substitute
# for a secret scanner in CI.
if rg -n --glob '*' '(^|[[:space:]])kind:[[:space:]]*Secret([[:space:]]|$)|-----BEGIN( [A-Z]+)? PRIVATE KEY-----|DO_NOT_PERSIST_' "$stage_directory" >/dev/null; then
  printf 'release bundle input crosses the non-sensitive artifact boundary\n' >&2
  exit 1
fi

node - "$stage_directory" "$source_revision" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [stage, revision] = process.argv.slice(2);

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(dir, entry.name);
    return entry.isDirectory() ? files(absolute) : [absolute];
  });
}

const entries = files(stage).map((absolute) => {
  const bytes = fs.readFileSync(absolute);
  return {
    path: path.relative(stage, absolute).split(path.sep).join('/'),
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    size: bytes.length,
  };
}).sort((a, b) => a.path.localeCompare(b.path));

const manifest = {
  schema_version: 'v1',
  artifact: { name: 'node-operator-release-bundle.tar', media_type: 'application/x-tar' },
  source_revision: revision,
  entries,
};
fs.writeFileSync(path.join(stage, 'bundle-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
NODE

mkdir -p "$output_directory"
artifact_path="$output_directory/node-operator-release-bundle.tar"

node - "$stage_directory" "$artifact_path" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [stage, destination] = process.argv.slice(2);

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(dir, entry.name);
    return entry.isDirectory() ? files(absolute) : [absolute];
  });
}
function octal(value, length) {
  return `${value.toString(8).padStart(length - 1, '0')}\0`;
}
function writeString(buffer, offset, length, value) {
  Buffer.from(value, 'utf8').copy(buffer, offset, 0, Math.min(Buffer.byteLength(value), length));
}
function header(name, size) {
  if (Buffer.byteLength(name) > 100) throw new Error(`tar entry name is too long: ${name}`);
  const block = Buffer.alloc(512, 0);
  writeString(block, 0, 100, name);
  writeString(block, 100, 8, octal(0o644, 8));
  writeString(block, 108, 8, octal(0, 8));
  writeString(block, 116, 8, octal(0, 8));
  writeString(block, 124, 12, octal(size, 12));
  writeString(block, 136, 12, octal(0, 12));
  block.fill(0x20, 148, 156);
  block[156] = '0'.charCodeAt(0);
  writeString(block, 257, 6, 'ustar\0');
  writeString(block, 263, 2, '00');
  const checksum = block.reduce((sum, byte) => sum + byte, 0);
  writeString(block, 148, 8, octal(checksum, 8));
  return block;
}

const output = fs.openSync(destination, 'w', 0o600);
try {
  for (const absolute of files(stage).sort()) {
    const bytes = fs.readFileSync(absolute);
    const name = path.relative(stage, absolute).split(path.sep).join('/');
    fs.writeSync(output, header(name, bytes.length));
    fs.writeSync(output, bytes);
    const padding = (512 - (bytes.length % 512)) % 512;
    if (padding) fs.writeSync(output, Buffer.alloc(padding));
  }
  fs.writeSync(output, Buffer.alloc(1024));
} finally {
  fs.closeSync(output);
}
NODE

artifact_hash="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
artifact_digest="sha256:$artifact_hash"
printf '%s  %s\n' "$artifact_digest" "$(basename "$artifact_path")" > "$output_directory/node-operator-release-bundle.sha256"

# Scan the already-built local file only.  Disable Syft's update check; Syft
# enrichment is disabled by default and is not enabled here.
SYFT_CHECK_FOR_APP_UPDATE=false syft scan "file:$artifact_path" \
  --source-name "$(basename "$artifact_path")" \
  --source-version "$artifact_digest" \
  --output "cyclonedx-json=$output_directory/sbom.cyclonedx.json" \
  --quiet
# A manifest-only archive can have no discoverable package components. Some
# Syft CycloneDX versions omit that optional field, while the release collector
# requires an array. Preserve an existing value exactly; add [] only if absent.
jq 'if has("components") then . else . + {components: []} end' \
  "$output_directory/sbom.cyclonedx.json" > "$temporary_directory/sbom.cyclonedx.json"
mv "$temporary_directory/sbom.cyclonedx.json" "$output_directory/sbom.cyclonedx.json"

node - "$stage_directory/bundle-manifest.json" "$output_directory/manifest.json" "$output_directory/provenance-input.json" "$artifact_digest" "$source_revision" <<'NODE'
const fs = require('node:fs');
const [contentsManifest, outputManifest, provenance, digest, revision] = process.argv.slice(2);
const contents = JSON.parse(fs.readFileSync(contentsManifest, 'utf8'));
const manifest = { ...contents, artifact: { ...contents.artifact, digest } };
const provenanceInput = {
  _type: 'https://in-toto.io/Statement/v1',
  subject: [{ name: 'node-operator-release-bundle.tar', digest: { sha256: digest.slice('sha256:'.length) } }],
  predicateType: 'https://slsa.dev/provenance/v1',
  predicate: {
    buildDefinition: {
      buildType: 'https://node-operator.example/release-bundle/v1',
      externalParameters: { bundle_format: 'deterministic-posix-tar-v1' },
      resolvedDependencies: [{ uri: 'git+node-operator', digest: { gitCommit: revision } }],
    },
    runDetails: { builder: { id: 'local://node-operator/scripts/ci/build-release-bundle.sh' } },
  },
};
fs.writeFileSync(outputManifest, `${JSON.stringify(manifest, null, 2)}\n`);
fs.writeFileSync(provenance, `${JSON.stringify(provenanceInput, null, 2)}\n`);
NODE

printf 'built %s\n' "$artifact_digest"
