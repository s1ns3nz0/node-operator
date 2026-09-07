#!/usr/bin/env bash
set -euo pipefail

# Verify a locally restored Object-Lock archive copy before using it for audit
# or reindexing. It never changes the original archive or any workload.
usage() { printf '%s\n' "Usage: ${0##*/} --manifest <absolute-json> --evidence-dir <absolute-dir>" >&2; exit 64; }
manifest=''; evidence_dir=''
while [ "$#" -gt 0 ]; do case "$1" in --manifest) manifest="${2:-}"; shift 2 ;; --evidence-dir) evidence_dir="${2:-}"; shift 2 ;; *) usage ;; esac; done
case "$manifest" in /*) ;; *) usage ;; esac
case "$evidence_dir" in /*) ;; *) usage ;; esac
for command in jq shasum basename dirname awk; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
[ -r "$manifest" ] && [ -d "$evidence_dir" ] || { printf '%s\n' 'manifest or restored evidence directory is not readable' >&2; exit 66; }
jq -e '.schema_version == 1 and .event_type == "archive-manifest" and (.records | type == "array" and length > 0)' "$manifest" >/dev/null || { printf '%s\n' 'invalid audit manifest' >&2; exit 65; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"; validator="$root/scripts/ops/validate-validator-evidence-envelope.sh"
while IFS=$'\t' read -r filename expected_sha; do
  case "$filename" in ''|*/*|.*) printf '%s\n' 'unsafe manifest file name' >&2; exit 65 ;; esac
  restored="$evidence_dir/$filename"
  [ -r "$restored" ] || { printf 'missing restored evidence file: %s\n' "$filename" >&2; exit 65; }
  actual_sha="$(shasum -a 256 "$restored" | awk '{print $1}')"
  [ "$actual_sha" = "$expected_sha" ] || { printf 'restore SHA mismatch: %s\n' "$filename" >&2; exit 65; }
  "$validator" --file "$restored" >/dev/null
done < <(jq -r '.records[] | [.file,.sha256] | @tsv' "$manifest")
printf '%s\n' 'PASS: restored validator evidence matches its manifest and non-secret schema.'
