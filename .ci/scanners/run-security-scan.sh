#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: %s EVIDENCE_DIRECTORY COMMIT_SHA BASE_SHA\n' "$0" >&2
  exit 64
fi

evidence_directory="$1"
commit_sha="$2"
base_sha="$3"
scanner_script_directory="${SCANNER_SCRIPT_DIRECTORY:-/opt/node-operator-scanner/scripts}"

# The release workflow publishes this runner and collector together. Until a
# newly published digest is promoted to CI, retain compatibility with the
# already-pinned tools-only image by using the checked-out runner and scripts.
if [ ! -x "$scanner_script_directory/collect-security-evidence.sh" ]; then
  scanner_script_directory=/workspace/scripts/ci
fi

mkdir -p "$evidence_directory"
git config --global --add safe.directory /workspace
exec "$scanner_script_directory/collect-security-evidence.sh" \
  "$evidence_directory" "$commit_sha" /workspace "$base_sha"
