#!/usr/bin/env bash
set -euo pipefail
umask 077

# v0.1.20 single-entry operator flow. This is an orchestration wrapper: the
# existing release and ceremony scripts remain the implementation boundary.
# Recovery shares and keystore passwords are collected by those scripts using
# silent prompts and are never accepted as command-line arguments here.

[ "$#" -eq 0 ] || { printf '%s\n' 'This release has one execution path and accepts no command-line options. Put non-secret overrides in ./env.' >&2; exit 64; }

bundle_root=''; env_file=''

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -z "$bundle_root" ]; then
  repo_candidate="$(cd "$script_dir/../.." && pwd -P)"
  bundle_candidate="$(cd "$script_dir/../../.." && pwd -P)"
  if [ -f "$bundle_candidate/bundle-manifest.json" ]; then bundle_root="$bundle_candidate"; else bundle_root="$repo_candidate"; fi
fi
case "$bundle_root" in /*) ;; *) printf '%s\n' 'bundle root must be absolute' >&2; exit 64 ;; esac
if [ -d "$bundle_root/source" ] && [ -f "$bundle_root/bundle-manifest.json" ]; then
  source_root="$bundle_root/source"
elif [ -f "$bundle_root/scripts/release/hoodi-validator-release.sh" ]; then
  # Local repository mode is useful for dry-run and shell validation only.
  source_root="$bundle_root"
else
  printf '%s\n' 'bundle root must be a verified v0.1.20 release layout (or a repository for dry-run)' >&2; exit 65
fi

release="$source_root/scripts/release/hoodi-validator-release.sh"
prepare="$source_root/scripts/release/prepare-hoodi-zero-release-inputs.sh"
keystore="$source_root/scripts/ops/generate-hoodi-validator-keystore.sh"
vault_tls="$source_root/scripts/release/prepare-vault-bootstrap-tls.sh"
for file in "$release" "$prepare" "$keystore" "$vault_tls"; do [ -x "$file" ] || { printf 'missing executable in release bundle: %s\n' "$file" >&2; exit 65; }; done
for command in aws jq find shasum; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

# Optional non-secret .env-style overrides. Values are never exported and
# unknown keys are ignored. This file may contain addresses/digests only.
if [ -z "$env_file" ] && [ -f "$bundle_root/env" ]; then env_file="$bundle_root/env"; fi
if [ -z "$env_file" ] && [ -f "$bundle_root/release/env" ]; then env_file="$bundle_root/release/env"; fi
if [ -n "$env_file" ]; then
  case "$env_file" in /*) ;; *) printf '%s\n' '--env-file must be absolute' >&2; exit 64 ;; esac
  [ -f "$env_file" ] && [ ! -L "$env_file" ] || { printf '%s\n' 'env file must be a regular file' >&2; exit 65; }
  while IFS='=' read -r key value; do
    key="${key%%[[:space:]]*}"; value="${value##[[:space:]]}"
    case "$key" in ''|'#'*) continue ;; esac
    case "$key" in REGION) DEFAULT_REGION="$value" ;; VALIDATOR_SET) DEFAULT_VALIDATOR_SET="$value" ;; VALIDATOR_PUBLIC_KEY) DEFAULT_VALIDATOR_KEY="$value" ;; WITHDRAWAL_ADDRESS) DEFAULT_WITHDRAWAL="$value" ;; WEB3SIGNER_IMAGE) DEFAULT_WEB3SIGNER_IMAGE="$value" ;; POSTGRES_IMAGE) DEFAULT_POSTGRES_IMAGE="$value" ;; PRYSM_IMAGE) DEFAULT_PRYSM_IMAGE="$value" ;; FENCE_IMAGE) DEFAULT_FENCE_IMAGE="$value" ;; BACKEND_PRINCIPAL_ARN) DEFAULT_BACKEND_PRINCIPAL_ARN="$value" ;; esac
  done < "$env_file"
fi
DEFAULT_REGION="${DEFAULT_REGION:-ap-northeast-2}"
DEFAULT_VALIDATOR_SET="${DEFAULT_VALIDATOR_SET:-hoodi-001}"
DEFAULT_VALIDATOR_KEY="${DEFAULT_VALIDATOR_KEY:-0xa3866b82651039224bfd725fc81e7ff17c1765021dff37f3fd4bc01405e2ed14c97c7c5c82cd95104d8f82c4229ab0d0}"
DEFAULT_WITHDRAWAL="${DEFAULT_WITHDRAWAL:-0x403FF64383B8ddf994D5563550c8040d89F025Ac}"
DEFAULT_WEB3SIGNER_IMAGE="${DEFAULT_WEB3SIGNER_IMAGE:-}"
DEFAULT_POSTGRES_IMAGE="${DEFAULT_POSTGRES_IMAGE:-}"
DEFAULT_PRYSM_IMAGE="${DEFAULT_PRYSM_IMAGE:-}"
DEFAULT_FENCE_IMAGE="${DEFAULT_FENCE_IMAGE:-}"
DEFAULT_BACKEND_PRINCIPAL_ARN="${DEFAULT_BACKEND_PRINCIPAL_ARN:-}"

[ -d "$bundle_root/source" ] && [ -f "$bundle_root/bundle-manifest.json" ] || {
  printf '%s\n' 'a verified v0.1.20 release bundle is required' >&2; exit 65;
}

[ -t 0 ] && [ -t 1 ] || { printf '%s\n' 'execute mode requires an interactive terminal' >&2; exit 69; }
printf '%s\n' 'This will apply the v0.1.20 release to the selected AWS account and Region.' >&2
printf 'Type DEPLOY to continue: ' >&2
IFS= read -r confirmation
[ "$confirmation" = 'DEPLOY' ] || { printf '%s\n' 'deployment cancelled' >&2; exit 0; }

prompt() { local label="$1" value; printf '%s: ' "$label" >&2; IFS= read -r value; printf '%s' "$value"; }
prompt_default() { local label="$1" fallback="$2" value; printf '%s [%s]: ' "$label" "$fallback" >&2; IFS= read -r value; printf '%s' "${value:-$fallback}"; }
prompt_secret() { local label="$1" value; printf '%s: ' "$label" >&2; IFS= read -r -s value; printf '\n' >&2; printf '%s' "$value"; }
absolute_new_dir() { case "$1" in /*) ;; *) printf '%s\n' 'path must be absolute' >&2; exit 64 ;; esac; [ ! -e "$1" ] && [ ! -L "$1" ] || { printf 'path already exists: %s\n' "$1" >&2; exit 65; }; }

region="$(prompt_default 'AWS Region' "$DEFAULT_REGION")"
case "$region" in ap-northeast-1|ap-northeast-2) ;; *) printf '%s\n' 'unsupported Region' >&2; exit 64 ;; esac
validator_set="$(prompt_default 'Validator set' "$DEFAULT_VALIDATOR_SET")"
validator_key="$(prompt_default 'Validator public key' "$DEFAULT_VALIDATOR_KEY")"
withdrawal="$(prompt_default 'Withdrawal address' "$DEFAULT_WITHDRAWAL")"
identity="$(aws sts get-caller-identity --output json)"
account="$(jq -er '.Account | select(test("^[0-9]{12}$"))' <<<"$identity")" || { printf '%s\n' 'AWS identity did not return a 12-digit account' >&2; exit 65; }
runtime_images="$source_root/.ci/validator/approved-runtime-images.json"
client_images="$source_root/.ci/validator/approved-client-images.json"
[ -f "$runtime_images" ] && [ -f "$client_images" ] || { printf '%s\n' 'release bundle lacks canonical approved image records' >&2; exit 65; }
web3signer_image="${DEFAULT_WEB3SIGNER_IMAGE:-$(jq -er '.images.web3signer.source' "$runtime_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-runtime-web3signer#")}"
postgres_image="${DEFAULT_POSTGRES_IMAGE:-$(jq -er '.images.postgres.source' "$runtime_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-runtime-postgres#")}"
prysm_image="${DEFAULT_PRYSM_IMAGE:-$(jq -er '[.images[] | select(.component == "prysm-validator" and .activation_approved == true) | .private_image][0]' "$client_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-prysm#")}"
[ "$prysm_image" != null ] && [ -n "$prysm_image" ] || { printf '%s\n' 'approved Prysm activation image is missing' >&2; exit 65; }
printf 'Using release-approved images: Web3Signer=%s PostgreSQL=%s Prysm=%s\n' "$web3signer_image" "$postgres_image" "$prysm_image" >&2
if [ -n "$DEFAULT_FENCE_IMAGE" ]; then
  fence_image="$DEFAULT_FENCE_IMAGE"
  printf 'Using env-file signing-fence image: %s\n' "$fence_image" >&2
else
  fence_image="$(prompt 'Approved signing-fence private ECR image@sha256 digest (v0.1.20 has no canonical default)')"
fi
api_cidr="$(prompt 'Kubernetes API operator IPv4 CIDR (/32)')"
output_dir="$(prompt 'New absolute working directory')"
absolute_new_dir "$output_dir"

zones=()
while IFS= read -r zone; do
  [ -n "$zone" ] && zones+=("$zone")
done < <(aws ec2 describe-availability-zones --region "$region" --filters Name=state,Values=available --query 'AvailabilityZones[].ZoneName' --output text | tr '\t' '\n' | sort | head -n 2)
[ "${#zones[@]}" -eq 2 ] || { printf '%s\n' 'could not discover two available Availability Zones' >&2; exit 65; }
mkdir -m 700 "$output_dir"
trap 'unset confirmation validator_key withdrawal web3signer_image postgres_image prysm_image fence_image; rm -f "$output_dir/.interactive-inputs.tmp" 2>/dev/null || true' EXIT

prepare_args=(--aws-account-id "$account" --aws-region "$region" --availability-zone "${zones[0]}" --availability-zone "${zones[1]}" --validator-set "$validator_set" --validator-public-key "$validator_key" --withdrawal-address "$withdrawal" --web3signer-image "$web3signer_image" --postgres-image "$postgres_image" --prysm-validator-image "$prysm_image" --signing-fence-image "$fence_image" --kubernetes-api-cidr "$api_cidr" --output-dir "$output_dir/inputs")
[ -n "$DEFAULT_BACKEND_PRINCIPAL_ARN" ] && prepare_args+=(--backend-principal-arn "$DEFAULT_BACKEND_PRINCIPAL_ARN")
"$prepare" "${prepare_args[@]}"
inputs="$output_dir/inputs/hoodi-zero-release-inputs.json"
session="$output_dir/private-eks-session.json"

"$release" deploy apply --bundle-root "$bundle_root" --inputs "$inputs" --work-dir "$output_dir/deployment-work" --private-eks-session-handoff "$session" --allow-create

printf '%s\n' 'Preparing cert-manager-managed Vault TLS through the private EKS session.' >&2
eks_env=(env PRIVATE_EKS_SESSION=1 AWS_REGION="$region" EKS_CLUSTER_NAME="$(jq -er '.cluster_name' "$session")" SSM_OPS_INSTANCE_ID="$(jq -er '.ssm_ops_instance_id' "$session")")
tls_manifest="$source_root/docs/gitops/vault-tls-internal-ca.example.yaml"
[ -f "$tls_manifest" ] && [ ! -L "$tls_manifest" ] || { printf '%s\n' 'release bundle lacks the reviewed Vault TLS manifest' >&2; exit 65; }
"$source_root/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$vault_tls" --manifest "$tls_manifest"

printf '%s\n' 'Next ceremony: Vault v2 recovery. Recovery shares will be requested silently by the delegated script.' >&2
"$bundle_root/source/scripts/ops/recover-and-bootstrap-hoodi-vault-v2.sh" --validator-set "$validator_set"

printf '%s\n' 'Generating validator keystore locally. The keystore password is handled by the generator and is not persisted by this wrapper.' >&2
mkdir -m 700 "$output_dir/custody"
"$keystore" --output-dir "$output_dir/custody"
"$release" custody apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --keystore-dir "$output_dir/custody/validator_keys" --ceremony-dir "$output_dir/ceremony"

mkdir -m 700 "$output_dir/evidence"
"$release" evidence signer --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --output-dir "$output_dir/evidence/signer"
"$release" evidence beacon --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --output-dir "$output_dir/evidence/beacon"

printf '%s\n' 'Activation requires independently reviewed deposit evidence. Enter paths only; secret material is not accepted.' >&2
deposit_attestation="$(prompt 'Absolute deposit attestation JSON')"
public_deposit="$(prompt 'Absolute public deposit verification JSON')"
private_evidence="$(prompt 'Absolute private Beacon evidence JSON')"
signer_evidence="$(prompt 'Absolute signer evidence JSON')"
confirm_key="$(prompt 'Confirm validator public key (0x...)')"
confirm_withdrawal="$(prompt 'Confirm withdrawal address (0x...)')"
"$release" activate apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --deposit-attestation "$deposit_attestation" --public-deposit-verification "$public_deposit" --private-evidence "$private_evidence" --signer-evidence "$signer_evidence" --confirm-public-key "$confirm_key" --confirm-withdrawal-address "$confirm_withdrawal"
printf 'PASS: v0.1.20 interactive Hoodi release completed. Non-secret handoffs and evidence are under %s.\n' "$output_dir"
