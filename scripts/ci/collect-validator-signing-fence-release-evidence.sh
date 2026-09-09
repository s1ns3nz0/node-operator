#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: %s PRIVATE_IMAGE_AT_DIGEST SOURCE_REVISION OUTPUT_JSON\n' "$0" >&2
  exit 64
fi

image="$1"; source_revision="$2"; output="$3"
[[ "$image" =~ ^[0-9]{12}\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/node-operator-baseline-validator-fence@sha256:[0-9a-f]{64}$ ]] || { printf 'image must be the exact private fence digest\n' >&2; exit 64; }
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { printf 'source revision must be a full lowercase Git SHA\n' >&2; exit 64; }
case "$output" in /*) ;; *) printf 'output must be absolute\n' >&2; exit 64 ;; esac
for command in cosign syft grype jq shasum mktemp mkdir mv rm date; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

umask 077
scratch="$(mktemp -d)"; temporary=''
cleanup() { set +e; [ -z "$temporary" ] || [ ! -e "$temporary" ] || rm -f "$temporary"; rm -rf "$scratch"; }
trap cleanup EXIT
identity='https://github.com/s1ns3nz0/node-operator/.github/workflows/validator-signing-fence-image.yml@refs/heads/main'
issuer='https://token.actions.githubusercontent.com'
digest="${image##*@}"

# These commands perform the cryptographic verification against the exact OCI
# digest. Their raw payloads remain in the private temporary directory.
cosign verify --certificate-identity "$identity" --certificate-oidc-issuer "$issuer" --certificate-github-workflow-sha "$source_revision" "$image" > "$scratch/signature.json"
cosign verify-attestation --type slsaprovenance1 --certificate-identity "$identity" --certificate-oidc-issuer "$issuer" --certificate-github-workflow-sha "$source_revision" "$image" > "$scratch/attestation.json"
cosign verify-attestation --type cyclonedx --certificate-identity "$identity" --certificate-oidc-issuer "$issuer" --certificate-github-workflow-sha "$source_revision" "$image" > "$scratch/sbom-attestation.json"
cosign verify-attestation --type vuln --certificate-identity "$identity" --certificate-oidc-issuer "$issuer" --certificate-github-workflow-sha "$source_revision" "$image" > "$scratch/scan-attestation.json"
signature_count="$(jq -s -e --arg digest "$digest" '
  (if length == 1 and (.[0] | type) == "array" then .[0] else . end) as $results |
  select(($results | length) > 0 and all($results[]; .critical.image["docker-manifest-digest"] == $digest)) |
  $results | length
' "$scratch/signature.json")" || { printf 'verified signature output is empty, malformed, or digest-mismatched\n' >&2; exit 1; }

jq -s -e --arg digest "$digest" --arg revision "$source_revision" '
  (if length == 1 and (.[0] | type) == "array" then .[0] else . end) |
  map(.payload | @base64d | fromjson) |
  any(.[];
    ._type == "https://in-toto.io/Statement/v0.1" and
    .predicateType == "https://slsa.dev/provenance/v1" and
    (.subject | any(.digest.sha256? == ($digest | sub("^sha256:"; "")))) and
    ((.predicate.buildDefinition.resolvedDependencies // []) | any(.digest.gitCommit? == $revision)) and
    (.predicate.runDetails.builder.id == "https://github.com/Attestations/GitHubHostedActions@v1") and
    .predicate.buildDefinition.buildType == "https://slsa.dev/container-based-build/v1")
' "$scratch/attestation.json" >/dev/null || { printf 'verified attestation does not bind the expected digest/source/builder\n' >&2; exit 1; }
jq -s -e --arg digest "$digest" '
  (if length == 1 and (.[0] | type) == "array" then .[0] else . end) |
  map(.payload | @base64d | fromjson) |
  any(.[]; .predicate.bomFormat == "CycloneDX" and .predicate.metadata.component.version == $digest)
' "$scratch/sbom-attestation.json" >/dev/null || { printf 'verified SBOM attestation is not bound to the image digest\n' >&2; exit 1; }
jq -s -e --arg digest "$digest" '
  (if length == 1 and (.[0] | type) == "array" then .[0] else . end) |
  map(.payload | @base64d | fromjson) |
  any(.[]; .predicate.artifact_digest == $digest and .predicate.status == "passed" and
    .predicate.findings.critical == 0 and .predicate.findings.high == 0 and .predicate.findings.unknown == 0)
' "$scratch/scan-attestation.json" >/dev/null || { printf 'verified vulnerability attestation does not contain a passing exact-digest decision\n' >&2; exit 1; }

SYFT_CHECK_FOR_APP_UPDATE=false syft scan "registry:$image" --source-name node-operator-baseline-validator-fence --source-version "$digest" --output "cyclonedx-json=$scratch/sbom.json"
jq -e --arg digest "$digest" '.bomFormat == "CycloneDX" and .metadata.component.version == $digest and (.components | type == "array")' "$scratch/sbom.json" >/dev/null || { printf 'SBOM is not bound to the exact image digest\n' >&2; exit 1; }
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/scan-release-sbom.sh" "$scratch/sbom.json" "$scratch/scan-summary.json"
jq -e '.status == "passed" and .findings.critical == 0 and .findings.high == 0 and .findings.unknown == 0' "$scratch/scan-summary.json" >/dev/null || { printf 'image vulnerability decision blocked promotion\n' >&2; exit 1; }

component_count="$(jq '.components | length' "$scratch/sbom.json")"
sbom_sha256="$(shasum -a 256 "$scratch/sbom.json" | awk '{print $1}')"
mkdir -p "$(dirname "$output")"; temporary="$(mktemp "${output}.tmp.XXXXXX")"
jq -n --arg image "$image" --arg digest "$digest" --arg revision "$source_revision" --arg identity "$identity" --arg issuer "$issuer" --arg collected "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sbom_sha256 "$sbom_sha256" --argjson signatures "$signature_count" --argjson components "$component_count" --slurpfile scan "$scratch/scan-summary.json" '
  {schema_version:1,event_type:"validator-signing-fence-release-verification",collected_at_utc:$collected,image:$image,artifact_digest:$digest,source_revision:$revision,result:"PASS",cryptographic_verification:{tool:"cosign",signature_count:$signatures,identity:$identity,issuer:$issuer,slsa_provenance:true,transparency_log_verified:true},sbom:{tool:"syft",format:"cyclonedx-json",component_count:$components,sha256:$sbom_sha256},vulnerability_scan:$scan[0]}
' > "$temporary"
mv "$temporary" "$output"; temporary=''
printf 'PASS: authenticated signing-fence release evidence written to %s\n' "$output"
