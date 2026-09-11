#!/usr/bin/env bash
# Check objective: Validate approved signer source.
set -euo pipefail

[[ "$SOURCE" =~ ^ghcr\.io/s1ns3nz0/node-operator/vault-release-signer@sha256:[a-f0-9]{64}$ ]] || {
  echo 'source must be the approved Vault signer GHCR repository pinned by a sha256 digest' >&2
  exit 1
}
echo "SOURCE_DIGEST=${SOURCE##*@}" >> "$GITHUB_ENV"
