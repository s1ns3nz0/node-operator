#!/usr/bin/env bash
set -euo pipefail

usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> --validator-public-key <0x-key> --prysm-validator-image <private-ecr@sha256> --signer-ca <absolute-pem> --output <absolute-yaml>" >&2; exit 64; }
validator_set=''; public_key=''; image=''; signer_ca=''; output=''
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) validator_set="${2:-}"; shift 2 ;; --validator-public-key) public_key="${2:-}"; shift 2 ;; --prysm-validator-image) image="${2:-}"; shift 2 ;; --signer-ca) signer_ca="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;; *) usage ;; esac; done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
case "$signer_ca" in /*) ;; *) usage ;; esac
case "$output" in /*) ;; *) usage ;; esac
printf '%s\n' "$image" | grep -Eq '^106760547719\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$' || { printf '%s\n' 'image must be an approved same-account private ECR digest' >&2; exit 65; }
if [ ! -s "$signer_ca" ] || ! grep -Fq -- '-----BEGIN CERTIFICATE-----' "$signer_ca"; then
  printf '%s\n' 'signer CA must be a non-empty PEM certificate' >&2
  exit 65
fi
for command in base64 sed mkdir mktemp mv grep dirname unlink tr; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"; template="$root/deploy/validator/client-template.yaml"
ca_b64="$(base64 < "$signer_ca" | tr -d '\n')"
mkdir -p "$(dirname "$output")"; temporary="$(mktemp "${output}.tmp.XXXXXX")"
cleanup() { set +e; [ -z "${temporary:-}" ] || [ ! -e "$temporary" ] || unlink "$temporary" 2>/dev/null || true; }; trap cleanup EXIT INT TERM
sed -e "s|REPLACE_WITH_VALIDATOR_SET|${validator_set}|g" -e "s|REPLACE_WITH_VALIDATOR_PUBLIC_KEY|${public_key}|g" -e "s|REPLACE_WITH_PRYSM_VALIDATOR_IMAGE|${image}|g" -e "s|REPLACE_WITH_SIGNER_CA_BASE64|${ca_b64}|g" "$template" > "$temporary"
grep -q 'REPLACE_WITH_' "$temporary" && { printf '%s\n' 'unresolved client placeholder' >&2; exit 65; }
mv "$temporary" "$output"; temporary=''
printf 'PASS: zero-replica validator client manifest rendered to %s.\n' "$output"
