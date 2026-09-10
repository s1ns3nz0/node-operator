#!/usr/bin/env bash
set -euo pipefail

usage() { printf '%s\n' "Usage: ${0##*/} --validator-set <hoodi-id> --validator-public-key <0x-key> --aws-account-id <12-digit-id> --prysm-validator-image <private-ecr@sha256> --signing-fence-image <private-ecr@sha256> --kubernetes-api-cidr <ipv4/32> --output <absolute-yaml>" >&2; exit 64; }
validator_set=''; public_key=''; aws_account_id=''; image=''; fence_image=''; kubernetes_api_cidr=''; output=''
while [ "$#" -gt 0 ]; do case "$1" in --validator-set) validator_set="${2:-}"; shift 2 ;; --validator-public-key) public_key="${2:-}"; shift 2 ;; --aws-account-id) aws_account_id="${2:-}"; shift 2 ;; --prysm-validator-image) image="${2:-}"; shift 2 ;; --signing-fence-image) fence_image="${2:-}"; shift 2 ;; --kubernetes-api-cidr) kubernetes_api_cidr="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;; *) usage ;; esac; done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
case "$aws_account_id" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) usage ;; esac
case "$output" in /*) ;; *) usage ;; esac
printf '%s\n' "$image" | grep -Eq "^${aws_account_id}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$" || { printf '%s\n' 'image must be an approved same-account private ECR digest' >&2; exit 65; }
printf '%s\n' "$fence_image" | grep -Eq "^${aws_account_id}\\.dkr\\.ecr\\.ap-northeast-2\\.amazonaws\\.com/node-operator-baseline-validator-fence@sha256:[a-f0-9]{64}$" || { printf '%s\n' 'fence image must be the protected type-separated private ECR digest' >&2; exit 65; }
printf '%s\n' "$kubernetes_api_cidr" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/32$' || { printf '%s\n' 'Kubernetes API CIDR must be one explicit IPv4 /32' >&2; exit 65; }
for command in sed mkdir mktemp mv grep dirname unlink jq; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"; template="$root/deploy/validator/client-template.yaml"; fence_template="$root/deploy/validator/client-lease-fence-template.yaml"
jq -e --arg image "$image" --arg account "$aws_account_id" '.schema_version == 2 and any(.images[]; .private_image == $image and (.private_image | startswith($account + ".dkr.ecr.ap-northeast-2.amazonaws.com/")) and .stage_approved == true and (.release_channel == "upstream-mirror" or .release_channel == "manual-native-mtls"))' "$root/.ci/validator/approved-client-images.json" >/dev/null || { printf '%s\n' 'private Prysm image is not an exact stage-approved reviewed artifact for this account' >&2; exit 65; }
mkdir -p "$(dirname "$output")"; temporary="$(mktemp "${output}.tmp.XXXXXX")"
cleanup() { set +e; [ -z "${temporary:-}" ] || [ ! -e "$temporary" ] || unlink "$temporary" 2>/dev/null || true; }; trap cleanup EXIT INT TERM
sed -e "s|REPLACE_WITH_VALIDATOR_SET|${validator_set}|g" -e "s|REPLACE_WITH_SIGNING_FENCE_IMAGE|${fence_image}|g" -e "s|REPLACE_WITH_KUBERNETES_API_CIDR|${kubernetes_api_cidr}|g" "$fence_template" > "$temporary"
printf '%s\n' '---' >> "$temporary"
sed -e "s|REPLACE_WITH_VALIDATOR_SET|${validator_set}|g" -e "s|REPLACE_WITH_VALIDATOR_PUBLIC_KEY|${public_key}|g" -e "s|REPLACE_WITH_PRYSM_VALIDATOR_IMAGE|${image}|g" "$template" >> "$temporary"
grep -q 'REPLACE_WITH_' "$temporary" && { printf '%s\n' 'unresolved client placeholder' >&2; exit 65; }
mv "$temporary" "$output"; temporary=''
printf 'PASS: zero-replica validator client manifest rendered to %s.\n' "$output"
