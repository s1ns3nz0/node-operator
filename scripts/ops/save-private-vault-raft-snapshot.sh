#!/usr/bin/env bash
set -euo pipefail

# Reads the administrator token only from the terminal. The local snapshot is
# removed on every exit after a verified, encrypted S3 upload.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
region="${AWS_REGION:-ap-northeast-2}"
bucket="${VAULT_SNAPSHOT_BUCKET:-}"
kms_key="alias/node-operator-baseline-vault-snapshot"

usage() { printf 'Usage: %s [--bucket BUCKET]\n' "${0##*/}" >&2; exit 64; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bucket) bucket="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
for command in aws vault jq mktemp shasum; do
  command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }
done

if [ -z "$bucket" ]; then
  bucket_arn="$(aws resourcegroupstaggingapi get-resources --region "$region" --resource-type-filters s3 --tag-filters Key=Purpose,Values=private-vault-raft-migration-backup --query 'ResourceTagMappingList[].ResourceARN' --output text)"
  case "$bucket_arn" in arn:aws:s3:::*) bucket="${bucket_arn#arn:aws:s3:::}" ;; *) printf 'unable to resolve the unique Vault snapshot bucket; pass --bucket explicitly\n' >&2; exit 65 ;; esac
fi

object_lock="$(aws s3api get-object-lock-configuration --bucket "$bucket" --region "$region" --output json)"
jq -e '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled" and .ObjectLockConfiguration.Rule.DefaultRetention.Mode == "GOVERNANCE" and .ObjectLockConfiguration.Rule.DefaultRetention.Days >= 90' <<<"$object_lock" >/dev/null || { printf 'snapshot bucket does not meet the Object Lock retention boundary\n' >&2; exit 65; }
encryption="$(aws s3api get-bucket-encryption --bucket "$bucket" --region "$region" --output json)"
jq -e '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm == "aws:kms"' <<<"$encryption" >/dev/null || { printf 'snapshot bucket does not enforce SSE-KMS\n' >&2; exit 65; }

snapshot_file="$(mktemp /private/tmp/node-operator-vault-raft.XXXXXX)"
chmod 600 "$snapshot_file"
trap 'unset VAULT_TOKEN; rm -f "$snapshot_file"' EXIT
read -r -s -p 'Vault administrator token: ' VAULT_TOKEN
printf '\n' >&2
export VAULT_TOKEN
"$root/scripts/ops/with-private-vault.sh" -- vault operator raft snapshot save "$snapshot_file"
"$root/scripts/ops/with-private-vault.sh" -- vault operator raft snapshot inspect -format=json "$snapshot_file" >/dev/null

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
object_key="raft-migration/${timestamp}.snap"
checksum="$(shasum -a 256 "$snapshot_file" | awk '{print $1}')"
aws s3 cp "$snapshot_file" "s3://${bucket}/${object_key}" --region "$region" --sse aws:kms --sse-kms-key-id "$kms_key" >/dev/null
metadata="$(aws s3api head-object --bucket "$bucket" --key "$object_key" --region "$region" --output json)"
jq -e --arg checksum "$checksum" '.ServerSideEncryption == "aws:kms" and .ObjectLockMode == "GOVERNANCE" and (.ObjectLockRetainUntilDate | type == "string") and (.ContentLength > 0) and ($checksum | test("^[0-9a-f]{64}$"))' <<<"$metadata" >/dev/null || { printf 'uploaded snapshot does not meet encryption, retention, or integrity boundaries\n' >&2; exit 65; }
printf 'PASS: encrypted immutable Raft snapshot saved as s3://%s/%s (sha256=%s).\n' "$bucket" "$object_key" "$checksum"
