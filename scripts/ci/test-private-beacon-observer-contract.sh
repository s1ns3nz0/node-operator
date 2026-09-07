#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
for observer in observe-private-hoodi-validator.sh observe-private-hoodi-validator-duties.sh; do
  file="$root/scripts/ops/$observer"
  grep -Fq "beacon_target='service/prysm-beacon'" "$file"
  grep -Fq 'get service prysm-beacon' "$file"
  grep -Fq 'app.kubernetes.io/name=prysm-beacon' "$file"
  grep -Fq 'expected exactly one Ready private Prysm Beacon Pod' "$file"
  grep -Fq "port-forward \"\$beacon_target\"" "$file"
done
printf '%s\n' 'PASS: private Beacon observers use the Service when available and otherwise require exactly one Ready Prysm Pod.'
