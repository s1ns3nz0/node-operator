#!/usr/bin/env bash
# Purpose: Canonicalize, Cosign-sign, verify, and archive redacted exact-head CI evidence.
# Inputs: EVIDENCE_DIRECTORY SUBJECT_SHA WORKFLOW_RUN_ID OUTPUT_DIRECTORY and CI_EVIDENCE_ARCHIVE_BUCKET.
# Outputs: Signed manifest and evidence objects under the dedicated S3 ci/ prefix.
set -euo pipefail
umask 077
[ "$#" -eq 4 ] || { printf 'usage: %s EVIDENCE_DIRECTORY SUBJECT_SHA WORKFLOW_RUN_ID OUTPUT_DIRECTORY\n' "$0" >&2; exit 64; }
evidence_directory="$1"; subject_sha="$2"; workflow_run_id="$3"; output_directory="$4"
[[ "$subject_sha" =~ ^[a-f0-9]{40}$ ]] || { printf 'subject SHA must be 40 lowercase hexadecimal characters\n' >&2; exit 64; }
[[ "$workflow_run_id" =~ ^[1-9][0-9]*$ ]] || { printf 'workflow run ID must be numeric\n' >&2; exit 64; }
[[ "$evidence_directory" = /* && "$output_directory" = /* ]] || { printf 'evidence and output directories must be absolute\n' >&2; exit 64; }
: "${CI_EVIDENCE_ARCHIVE_BUCKET:?CI_EVIDENCE_ARCHIVE_BUCKET is required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
test -d "$evidence_directory" && test ! -L "$evidence_directory"
jq -e --arg sha "$subject_sha" '.subject.commit_sha == $sha' "$evidence_directory/evidence.json" >/dev/null
jq -e '.summary.block == 0 and .summary.require_approval == 0 and (.violations | type == "array")' "$evidence_directory/decision.json" >/dev/null
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch" "$output_directory"' EXIT
mkdir -m 0700 -p "$output_directory"
for file in evidence.json decision.json cache-context.json baseline-summary.json; do
  [ -f "$evidence_directory/$file" ] && cp -p "$evidence_directory/$file" "$output_directory/$file"
done
find "$output_directory" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort > "$scratch/members"
python3 - "$output_directory" "$subject_sha" "$workflow_run_id" "$scratch/members" > "$output_directory/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1]); subject = sys.argv[2]; run_id = sys.argv[3]; members = pathlib.Path(sys.argv[4])
items=[]
for name in members.read_text().splitlines():
    if name not in {"evidence.json","decision.json","cache-context.json","baseline-summary.json"}: raise SystemExit(f"unexpected evidence member: {name}")
    items.append({"name":name,"sha256":hashlib.sha256((root/name).read_bytes()).hexdigest()})
print(json.dumps({"schema_version":1,"subject_sha":subject,"workflow_run_id":int(run_id),"members":items}, sort_keys=True, separators=(",",":")))
PY
scripts/ci/install-validator-signing-fence-release-tools.sh "$scratch/cosign-tools"
export PATH="$scratch/cosign-tools:$PATH"
cosign sign-blob --yes --bundle "$output_directory/manifest.sigstore.json" "$output_directory/manifest.json"
identity="${COSIGN_CERTIFICATE_IDENTITY:-https://github.com/s1ns3nz0/node-operator/.github/workflows/evidence-archive.yml@refs/heads/main}"
cosign verify-blob --bundle "$output_directory/manifest.sigstore.json" --certificate-identity "$identity" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --certificate-github-workflow-repository 's1ns3nz0/node-operator' \
  --certificate-github-workflow-ref 'refs/heads/main' --certificate-github-workflow-trigger workflow_run \
  "$output_directory/manifest.json" >/dev/null
prefix="ci/$subject_sha/$workflow_run_id"
for file in "$output_directory"/*; do
  [ -f "$file" ] || continue
  aws s3 cp "$file" "s3://$CI_EVIDENCE_ARCHIVE_BUCKET/$prefix/$(basename "$file")" --only-show-errors
done
aws s3api head-object --bucket "$CI_EVIDENCE_ARCHIVE_BUCKET" --key "$prefix/manifest.sigstore.json" >/dev/null
printf 'PASS: Cosign-signed CI evidence verified and archived at s3://%s/%s/\n' "$CI_EVIDENCE_ARCHIVE_BUCKET" "$prefix"
