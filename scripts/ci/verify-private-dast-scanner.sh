#!/usr/bin/env bash
set -euo pipefail

contract="${1:-}"
test -f "$contract" || { printf 'missing approved DAST scanner allowlist\n' >&2; exit 64; }
jq -e '
  .schema_version == "v1" and
  .source == "ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef" and
  .profile == "baseline-passive" and
  (.approval_id | test("^[a-z0-9-]+$"))
' "$contract" >/dev/null
printf 'PASS: approved private DAST scanner digest is pinned.\n'
