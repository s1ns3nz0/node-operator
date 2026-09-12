#!/usr/bin/env bash
# Purpose: The sole public deployment entrypoint for the downloaded release.
# Inputs: No command-line options; the interactive flow asks only for required
# non-secret values and ceremony inputs at the appropriate boundary.
# Outputs: A complete Hoodi validator deployment or a resumable private handoff.
# Side effects: The same guarded release flow provisions infrastructure, private
# access, Vault, workloads, custody and activation in dependency order.
set -euo pipefail
[ "$#" -eq 0 ] || { printf '%s\n' 'This is the sole release entrypoint and accepts no command-line options. Run it without arguments.' >&2; exit 64; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../.." && pwd -P)"

# A checked-out repository does not contain the outer verified-bundle
# manifest. Build that manifest locally so the public command remains a
# genuine single entrypoint for developers and release consumers alike.
if [ ! -f "$repo_root/bundle-manifest.json" ] && [ -f "$repo_root/scripts/ci/build-release-bundle.sh" ]; then
  command -v mktemp >/dev/null 2>&1 || { printf '%s\n' 'missing command: mktemp' >&2; exit 69; }
  command -v tar >/dev/null 2>&1 || { printf '%s\n' 'missing command: tar' >&2; exit 69; }
  bundle_output="$(mktemp -d "${TMPDIR:-/tmp}/node-operator-release.XXXXXX")"
  bundle_root="$(mktemp -d "${TMPDIR:-/tmp}/node-operator-bundle.XXXXXX")"
  cleanup() { rm -rf -- "$bundle_output" "$bundle_root"; }
  trap cleanup EXIT INT TERM
  printf '%s\n' 'No verified bundle detected; building and validating a local release bundle.' >&2
  "$repo_root/scripts/ci/build-release-bundle.sh" "$bundle_output"
  tar -xf "$bundle_output/node-operator-release-bundle.tar" -C "$bundle_root"
  "$bundle_root/source/scripts/release/interactive-hoodi-release.sh"
  exit $?
fi

exec "$script_dir/interactive-hoodi-release.sh"
