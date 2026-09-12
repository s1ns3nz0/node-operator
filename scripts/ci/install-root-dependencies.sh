#!/usr/bin/env bash
# Check objective: Install the repository's locked Node.js dependencies for harness validation.
set -euo pipefail
test -f package.json
if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi
