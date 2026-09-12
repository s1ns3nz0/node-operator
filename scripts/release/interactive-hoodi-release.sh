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
deposit_validate="$source_root/scripts/ops/validate-hoodi-deposit-data.sh"
vault_tls="$source_root/scripts/release/prepare-vault-bootstrap-tls.sh"
for file in "$release" "$prepare" "$keystore" "$deposit_validate" "$vault_tls"; do [ -x "$file" ] || { printf 'missing executable in release bundle: %s\n' "$file" >&2; exit 65; }; done
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
    case "$key" in REGION) DEFAULT_REGION="$value" ;; DEPLOYMENT_NAME) DEFAULT_DEPLOYMENT_NAME="$value" ;; VALIDATOR_SET) DEFAULT_VALIDATOR_SET="$value" ;; VALIDATOR_PUBLIC_KEY) DEFAULT_VALIDATOR_KEY="$value" ;; WITHDRAWAL_ADDRESS) DEFAULT_WITHDRAWAL="$value" ;; EXISTING_KEYSTORE_DIR) DEFAULT_KEYSTORE_DIR="$value" ;; WEB3SIGNER_IMAGE) DEFAULT_WEB3SIGNER_IMAGE="$value" ;; POSTGRES_IMAGE) DEFAULT_POSTGRES_IMAGE="$value" ;; PRYSM_IMAGE) DEFAULT_PRYSM_IMAGE="$value" ;; FENCE_IMAGE) DEFAULT_FENCE_IMAGE="$value" ;; BACKEND_PRINCIPAL_ARN) DEFAULT_BACKEND_PRINCIPAL_ARN="$value" ;; ARGOCD_BOOTSTRAP_IMAGE) DEFAULT_ARGOCD_BOOTSTRAP_IMAGE="$value" ;; VAULT_BOOTSTRAP_IMAGE) DEFAULT_VAULT_BOOTSTRAP_IMAGE="$value" ;; CLIENT_CHART_VERSION) DEFAULT_CLIENT_CHART_VERSION="$value" ;; CLIENT_CHART_DIGEST) DEFAULT_CLIENT_CHART_DIGEST="$value" ;; CLIENT_CHART_SOURCE_REGION) DEFAULT_CLIENT_CHART_SOURCE_REGION="$value" ;; VAULT_CHART_VERSION) DEFAULT_VAULT_CHART_VERSION="$value" ;; VAULT_CHART_DIGEST) DEFAULT_VAULT_CHART_DIGEST="$value" ;; esac
  done < "$env_file"
fi
DEFAULT_REGION="${DEFAULT_REGION:-ap-northeast-2}"
# Fresh runs must not accidentally adopt a prior baseline. Keep an explicit
# env override available, but default to a compact UTC date/time deployment name.
# The 20-character Terraform naming limit requires a short prefix and YYMMDDHHMM.
DEFAULT_DEPLOYMENT_NAME="${DEFAULT_DEPLOYMENT_NAME:-node-op-$(date -u +%y%m%d%H%M)}"
DEFAULT_KEYSTORE_DIR="${DEFAULT_KEYSTORE_DIR:-}"
DEFAULT_VALIDATOR_SET="${DEFAULT_VALIDATOR_SET:-hoodi-001}"
DEFAULT_VALIDATOR_KEY="${DEFAULT_VALIDATOR_KEY:-}"
DEFAULT_WITHDRAWAL="${DEFAULT_WITHDRAWAL:-0x403FF64383B8ddf994D5563550c8040d89F025Ac}"
DEFAULT_WEB3SIGNER_IMAGE="${DEFAULT_WEB3SIGNER_IMAGE:-}"
DEFAULT_POSTGRES_IMAGE="${DEFAULT_POSTGRES_IMAGE:-}"
DEFAULT_PRYSM_IMAGE="${DEFAULT_PRYSM_IMAGE:-}"
DEFAULT_FENCE_IMAGE="${DEFAULT_FENCE_IMAGE:-}"
DEFAULT_BACKEND_PRINCIPAL_ARN="${DEFAULT_BACKEND_PRINCIPAL_ARN:-}"
DEFAULT_ARGOCD_BOOTSTRAP_IMAGE="${DEFAULT_ARGOCD_BOOTSTRAP_IMAGE:-}"
DEFAULT_VAULT_BOOTSTRAP_IMAGE="${DEFAULT_VAULT_BOOTSTRAP_IMAGE:-}"
DEFAULT_CLIENT_CHART_VERSION="${DEFAULT_CLIENT_CHART_VERSION:-}"
DEFAULT_CLIENT_CHART_DIGEST="${DEFAULT_CLIENT_CHART_DIGEST:-}"
DEFAULT_CLIENT_CHART_SOURCE_REGION="${DEFAULT_CLIENT_CHART_SOURCE_REGION:-ap-northeast-2}"
DEFAULT_VAULT_CHART_VERSION="${DEFAULT_VAULT_CHART_VERSION:-0.31.0}"
DEFAULT_VAULT_CHART_DIGEST="${DEFAULT_VAULT_CHART_DIGEST:-sha256:85cfa6b40396a198a104fbf06c7cccaf75428db7201394f9061c272441bcd0e4}"

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
if [ -t 2 ]; then ui_reset=$'\033[0m'; ui_cyan=$'\033[1;36m'; ui_green=$'\033[1;32m'; ui_yellow=$'\033[1;33m'; ui_red=$'\033[1;31m'; else ui_reset=''; ui_cyan=''; ui_green=''; ui_yellow=''; ui_red=''; fi
step_number=0
step() { step_number=$((step_number + 1)); printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n%s◆ STEP %02d/10%s  %s%s%s\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$ui_cyan" "$ui_reset" "$ui_cyan" "$step_number" "$ui_reset" "$ui_green" "$1" "$ui_reset" "$ui_cyan" "$ui_reset" >&2; }
display_digest() { case "$1" in *@sha256:????????????????????????????????????????????????????????????????) printf '%s@sha256:%s...%s' "${1%@*}" "${1##*@sha256:}" "${1: -8}" ;; *) printf '%s' "$1" ;; esac; }
absolute_new_dir() { case "$1" in /*) ;; *) printf '%s\n' 'path must be absolute' >&2; exit 64 ;; esac; [ ! -e "$1" ] && [ ! -L "$1" ] || { printf 'path already exists: %s\n' "$1" >&2; exit 65; }; }

step 'Collecting deployment settings'
region="$(prompt_default 'AWS Region' "$DEFAULT_REGION")"
case "$region" in ap-northeast-1|ap-northeast-2) ;; *) printf '%s\n' 'unsupported Region' >&2; exit 64 ;; esac
validator_set="$(prompt_default 'Validator set' "$DEFAULT_VALIDATOR_SET")"
deployment_name="$(prompt_default 'Deployment name' "$DEFAULT_DEPLOYMENT_NAME")"
[[ "$deployment_name" =~ ^[a-z][a-z0-9-]{1,18}[a-z0-9]$ ]] || { printf '%s\n' 'deployment name must be a DNS-compatible name of 3-20 characters' >&2; exit 64; }
withdrawal="$(prompt_default 'Withdrawal address' "$DEFAULT_WITHDRAWAL")"
identity="$(aws sts get-caller-identity --output json)"
account="$(jq -er '.Account | select(test("^[0-9]{12}$"))' <<<"$identity")" || { printf '%s\n' 'AWS identity did not return a 12-digit account' >&2; exit 65; }
printf 'Detected AWS account: %s\nType CONFIRM to continue with this account: ' "$account" >&2
IFS= read -r account_confirmation
[ "$account_confirmation" = 'CONFIRM' ] || { printf '%s\n' 'AWS account confirmation cancelled' >&2; exit 0; }
DEFAULT_BACKEND_PRINCIPAL_ARN="${DEFAULT_BACKEND_PRINCIPAL_ARN:-arn:aws:iam::${account}:role/NodeOperatorTerraformApply}"
if [ -n "$DEFAULT_BACKEND_PRINCIPAL_ARN" ]; then
  case "$DEFAULT_BACKEND_PRINCIPAL_ARN" in
    "arn:aws:iam::${account}:role/"*) ;;
    *) printf '%s\n' 'BACKEND_PRINCIPAL_ARN must be a same-account IAM role ARN' >&2; exit 65 ;;
  esac
  backend_role_name="${DEFAULT_BACKEND_PRINCIPAL_ARN##*/}"
  backend_role_created=false
  if ! aws iam get-role --role-name "$backend_role_name" --query 'Role.Arn' --output text >/dev/null 2>&1; then
    printf 'Configured Terraform backend role does not exist: %s\n' "$DEFAULT_BACKEND_PRINCIPAL_ARN" >&2
    printf 'Type CREATE to create this least-privilege bootstrap role (or press Enter to cancel): ' >&2
    IFS= read -r create_role_confirmation
    [ "$create_role_confirmation" = 'CREATE' ] || { printf '%s\n' 'backend role creation cancelled; no resources were changed' >&2; exit 0; }
    caller_arn="$(jq -er '.Arn' <<<"$identity")"
    case "$caller_arn" in
      arn:aws:iam::${account}:user/*) trust_principal="$caller_arn" ;;
      arn:aws:sts::${account}:assumed-role/*/*) trust_principal="arn:aws:iam::${account}:role/${caller_arn#arn:aws:sts::${account}:assumed-role/}"; trust_principal="${trust_principal%/*}" ;;
      *) printf '%s\n' 'current AWS identity cannot be used as a backend-role trust principal' >&2; exit 65 ;;
    esac
    trust_document="$(jq -cn --arg principal "$trust_principal" '{Version:"2012-10-17",Statement:[{Sid:"AllowInteractiveBootstrapCaller",Effect:"Allow",Principal:{AWS:$principal},Action:"sts:AssumeRole"}]}')"
    aws iam create-role --role-name "$backend_role_name" --assume-role-policy-document "$trust_document" --description 'Node Operator Terraform bootstrap state access' >/dev/null
    backend_role_created=true
    printf 'Created backend role %s with trust restricted to the current AWS identity.\n' "$backend_role_name" >&2
  fi
fi
platform_approval="$source_root/release/platform-artifact-approval.json"
if [ -f "$platform_approval" ]; then
  approval_schema="$(jq -er '.schema_version' "$platform_approval" 2>/dev/null || true)"
  [ "$approval_schema" = 1 ] || { printf '%s\n' 'platform artifact approval is malformed' >&2; exit 65; }
  if [ -z "$DEFAULT_ARGOCD_BOOTSTRAP_IMAGE" ]; then
    argo_digest="$(jq -er '.artifacts.argocd_bootstrap.source | split("@")[-1]' "$platform_approval")"
    DEFAULT_ARGOCD_BOOTSTRAP_IMAGE="${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-gitops-argocd@${argo_digest}"
  fi
  if [ -z "$DEFAULT_VAULT_BOOTSTRAP_IMAGE" ]; then
    vault_digest="$(jq -er '.artifacts.vault_bootstrap.source | split("@")[-1]' "$platform_approval")"
    DEFAULT_VAULT_BOOTSTRAP_IMAGE="${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-gitops-vault@${vault_digest}"
  fi
fi
runtime_images="$source_root/.ci/validator/approved-runtime-images.json"
client_images="$source_root/.ci/validator/approved-client-images.json"
[ -f "$runtime_images" ] && [ -f "$client_images" ] || { printf '%s\n' 'release bundle lacks canonical approved image records' >&2; exit 65; }
web3signer_image="${DEFAULT_WEB3SIGNER_IMAGE:-$(jq -er '.images.web3signer.source' "$runtime_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-runtime-web3signer#")}"
postgres_image="${DEFAULT_POSTGRES_IMAGE:-$(jq -er '.images.postgres.source' "$runtime_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-runtime-postgres#")}"
prysm_image="${DEFAULT_PRYSM_IMAGE:-$(jq -er '[.images[] | select(.component == "prysm-validator" and .activation_approved == true) | .private_image][0]' "$client_images" | sed "s#^[^@]*#${account}.dkr.ecr.${region}.amazonaws.com/node-operator-baseline-validator-prysm#")}"
[ "$prysm_image" != null ] && [ -n "$prysm_image" ] || { printf '%s\n' 'approved Prysm activation image is missing' >&2; exit 65; }
printf 'Using release-approved images:\n  Web3Signer %s\n  PostgreSQL %s\n  Prysm %s\n' "$(display_digest "$web3signer_image")" "$(display_digest "$postgres_image")" "$(display_digest "$prysm_image")" >&2
if [ -n "$DEFAULT_FENCE_IMAGE" ]; then
  fence_image="$DEFAULT_FENCE_IMAGE"
  printf 'Using env-file signing-fence image: %s\n' "$fence_image" >&2
else
  fence_image="$(prompt 'Approved signing-fence private ECR image@sha256 digest (v0.1.20 has no canonical default)')"
fi
# The signing-fence policy targets the private EKS API endpoint, which does not
# exist until foundation/EKS creation. A guarded deploy step replaces this
# staging sentinel with the endpoint's resolved private IPv4 before any
# validator manifest is applied.
api_cidr='127.0.0.1/32'
if [ -n "${NODE_OPERATOR_SOURCE_REPOSITORY_ROOT:-}" ]; then
  default_output_dir="${TMPDIR:-/tmp}/node-operator-run-$(date -u +%Y%m%dT%H%M%SZ)"
else
  default_output_dir="${PWD}/node-operator-run-$(date -u +%Y%m%dT%H%M%SZ)"
fi
output_dir="$(prompt_default 'New absolute working directory' "$default_output_dir")"
absolute_new_dir "$output_dir"
protected_repository_root="${NODE_OPERATOR_SOURCE_REPOSITORY_ROOT:-}"
if [ -n "$protected_repository_root" ]; then
  protected_repository_root="$(cd "$protected_repository_root" && pwd -P)"
  case "$output_dir" in
    "$protected_repository_root"|"$protected_repository_root"/*) printf '%s\n' 'working directory must be outside the source repository' >&2; exit 64 ;;
  esac
fi
trap 'unset confirmation validator_key expected_key withdrawal web3signer_image postgres_image prysm_image fence_image ecr_auth source_image; rm -f "$output_dir/.interactive-inputs.tmp" 2>/dev/null || true' EXIT

# Collect and verify the immutable platform bootstrap artifacts before creating
# any foundation resources. A missing mirror must fail closed without leaving a
# partially-created baseline behind.
argocd_bootstrap_image="${DEFAULT_ARGOCD_BOOTSTRAP_IMAGE:-$(prompt 'Private ECR Argo bootstrap image@sha256 digest')}"
vault_bootstrap_image="${DEFAULT_VAULT_BOOTSTRAP_IMAGE:-$(prompt 'Private ECR Vault bootstrap image@sha256 digest')}"
verify_private_image() {
  local image="$1" repository digest found
  repository="${image#*/}"; repository="${repository%@*}"; digest="${image##*@}"
  [[ "$image" =~ ^${account}\.dkr\.ecr\.${region//./\.}\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$ ]] || {
    printf 'bootstrap image must be a same-account private ECR digest: %s\n' "$image" >&2; exit 65;
  }
  found="$(aws ecr describe-images --region "$region" --repository-name "$repository" --image-ids imageDigest="$digest" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
  if [ "$found" != "$digest" ]; then
    printf 'required private ECR image is missing; it will be mirrored from the release approval: %s\n' "$image" >&2
    return 1
  fi
}
bootstrap_mirror_images=()
if ! verify_private_image "$argocd_bootstrap_image"; then bootstrap_mirror_images+=("$argocd_bootstrap_image"); fi
if ! verify_private_image "$vault_bootstrap_image"; then bootstrap_mirror_images+=("$vault_bootstrap_image"); fi

step 'Preparing and validating validator key'
printf '%s\n' 'Existing key is reused when configured; otherwise a new Hoodi ceremony runs.' >&2
mkdir -m 700 "$output_dir" "$output_dir/custody"
keystore_dir_for_custody="$output_dir/custody/validator_keys"
existing_keystore_dir="$DEFAULT_KEYSTORE_DIR"
if [ -z "$existing_keystore_dir" ]; then
  existing_keystore_dir="$(prompt_default 'Existing validator keystore directory (blank to generate a new key)' '')"
fi
if [ -n "$existing_keystore_dir" ]; then
  case "$existing_keystore_dir" in /*) ;; *) printf '%s\n' 'existing keystore directory must be absolute' >&2; exit 64 ;; esac
  [ -d "$existing_keystore_dir" ] && [ ! -L "$existing_keystore_dir" ] || { printf '%s\n' 'existing keystore directory must be a real directory' >&2; exit 65; }
  existing_keystore_dir="$(cd "$existing_keystore_dir" && pwd -P)"
  if [ -n "$protected_repository_root" ]; then
    case "$existing_keystore_dir" in
      "$protected_repository_root"|"$protected_repository_root"/*) printf '%s\n' 'existing keystore directory must be outside the source repository' >&2; exit 64 ;;
    esac
  fi
  existing_keystore="$(find "$existing_keystore_dir" -maxdepth 1 -type f -name 'keystore-*.json' -print)"
  existing_deposit="$(find "$existing_keystore_dir" -maxdepth 1 -type f -name 'deposit_data-*.json' -print)"
  [ "$(printf '%s\n' "$existing_keystore" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || { printf '%s\n' 'existing keystore directory must contain exactly one keystore-*.json' >&2; exit 65; }
  [ "$(printf '%s\n' "$existing_deposit" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || { printf '%s\n' 'existing keystore directory must contain exactly one deposit_data-*.json' >&2; exit 65; }
  keystore_dir_for_custody="$existing_keystore_dir"
  deposit_data="$existing_deposit"
  printf '%s\n' 'Using the existing validator keystore; no private key material will be copied.' >&2
else
  HOODI_WITHDRAWAL_ADDRESS="$withdrawal" "$keystore" --output-dir "$output_dir/custody"
  deposit_data="$(find "$output_dir/custody" -maxdepth 2 -type f -name 'deposit_data-*.json' -print)"
  [ "$(printf '%s\n' "$deposit_data" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || { printf '%s\n' 'key ceremony did not produce exactly one deposit-data file' >&2; exit 65; }
  keystore_dir_for_custody="$output_dir/custody/validator_keys"
fi
mkdir -m 700 "$output_dir/custody/public-attestation"
"$deposit_validate" --deposit-data "$deposit_data" --withdrawal-address "$withdrawal" --output-dir "$output_dir/custody/public-attestation" >/dev/null
deposit_attestation="$output_dir/custody/public-attestation/uc-1-deposit-attestation.json"
validator_key="$(jq -er '.validator_public_key' "$deposit_attestation" | tr '[:upper:]' '[:lower:]')"
if [ -n "$DEFAULT_VALIDATOR_KEY" ]; then
  expected_key="$(printf '%s' "$DEFAULT_VALIDATOR_KEY" | tr '[:upper:]' '[:lower:]')"
  [ "$validator_key" = "$expected_key" ] || { printf '%s\n' 'generated validator public key does not match VALIDATOR_PUBLIC_KEY; refusing to continue' >&2; exit 65; }
fi

# Hoodi registration is an operator-owned, on-chain action. The installer
# prepares and validates public deposit data but never handles a wallet,
# broadcasts a transaction, or accepts a private key. Keep this guidance next
# to the key ceremony so a fresh operator cannot mistake custody onboarding for
# testnet registration.
registration_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '\n%s╭────────────────────────────────────────────────────────────╮%s\n' "$ui_cyan" "$ui_reset" >&2
printf '%s│ HOODI TESTNET REGISTRATION  %s│%s\n' "$ui_cyan" "$registration_timestamp" "$ui_reset" >&2
printf '%s╰────────────────────────────────────────────────────────────╯%s\n' "$ui_cyan" "$ui_reset" >&2
printf '%s1.%s Review the public attestation: %s\n' "$ui_yellow" "$ui_reset" "$deposit_attestation" >&2
printf '%s2.%s Open the official Hoodi Launchpad and upload the matching deposit_data JSON:\n' "$ui_yellow" "$ui_reset" >&2
printf '   https://hoodi.launchpad.ethereum.org/\n' >&2
printf '%s3.%s Confirm network=Hoodi, amount=32 HoodiETH, validator public key, and withdrawal credentials match the attestation.\n' "$ui_yellow" "$ui_reset" >&2
printf '%s4.%s Connect your own Hoodi wallet and submit exactly one 32 HoodiETH deposit through the Launchpad.\n' "$ui_yellow" "$ui_reset" >&2
printf '%s5.%s Save the mined transaction hash; it is required for public receipt verification before activation.\n' "$ui_yellow" "$ui_reset" >&2
printf '%s!%s Do not paste mnemonics, keystore passwords, private keys, or wallet credentials into this shell, Git, CI, or Vault.\n' "$ui_red" "$ui_reset" >&2
printf '   Deposit data directory: %s\n' "$(dirname "$deposit_data")" >&2
printf '   Registration is intentionally manual and must be completed with your own Hoodi wallet.\n' >&2
while :; do
  registration_confirmation="$(prompt 'Have you completed and confirmed the 32 HoodiETH deposit? [yes/no]')"
  case "$(printf '%s' "$registration_confirmation" | tr '[:upper:]' '[:lower:]')" in
    yes|y|예|완료)
      printf '%s✓%s Hoodi deposit completion acknowledged; continuing to infrastructure and Vault setup.\n' "$ui_green" "$ui_reset" >&2
      break
      ;;
    no|n|'')
      printf '%s✖%s Hoodi registration not confirmed; stopping before infrastructure/Vault changes.\n' "$ui_red" "$ui_reset" >&2
      exit 0
      ;;
    *)
      printf '%s!%s Please answer yes or no.\n' "$ui_yellow" "$ui_reset" >&2
      ;;
  esac
done

zones=()
while IFS= read -r zone; do
  [ -n "$zone" ] && zones+=("$zone")
done < <(aws ec2 describe-availability-zones --region "$region" --filters Name=state,Values=available --query 'AvailabilityZones[].ZoneName' --output text | tr '\t' '\n' | sort | sed -n '1,2p')
[ "${#zones[@]}" -eq 2 ] || { printf '%s\n' 'could not discover two available Availability Zones' >&2; exit 65; }
# AWS Config permits only one recorder and delivery channel per Region. Reuse
# an existing account-wide recorder rather than attempting a second one.
manage_config_recorder=true
config_recorder_count="$(aws configservice describe-configuration-recorders --region "$region" --query 'length(ConfigurationRecorders)' --output text 2>/dev/null || printf '0')"
case "$config_recorder_count" in ''|None|0) ;; *) manage_config_recorder=false ;; esac
if [ "$manage_config_recorder" = false ]; then
  printf '%s\n' 'Reusing the existing regional AWS Config recorder; no duplicate recorder will be created.' >&2
fi
prepare_args=(--aws-account-id "$account" --aws-region "$region" --name "$deployment_name" --availability-zone "${zones[0]}" --availability-zone "${zones[1]}" --validator-set "$validator_set" --validator-public-key "$validator_key" --withdrawal-address "$withdrawal" --web3signer-image "$web3signer_image" --postgres-image "$postgres_image" --prysm-validator-image "$prysm_image" --signing-fence-image "$fence_image" --kubernetes-api-cidr "$api_cidr" --output-dir "$output_dir/inputs")
prepare_args+=(--manage-config-recorder "$manage_config_recorder")
[ -n "$DEFAULT_BACKEND_PRINCIPAL_ARN" ] && prepare_args+=(--backend-principal-arn "$DEFAULT_BACKEND_PRINCIPAL_ARN")
"$prepare" "${prepare_args[@]}"
inputs="$output_dir/inputs/hoodi-zero-release-inputs.json"
session="$output_dir/private-eks-session.json"

step 'Applying zero-resource foundation and private EKS'
"$release" deploy apply --bundle-root "$bundle_root" --inputs "$inputs" --work-dir "$output_dir/deployment-work" --private-eks-session-handoff "$session" --allow-create

if [ "${backend_role_created:-false}" = true ]; then
  bootstrap_output="$output_dir/deployment-work/bootstrap-output.json"
  [ -f "$bootstrap_output" ] || { printf '%s\n' 'bootstrap did not emit state outputs for backend-role policy binding' >&2; exit 65; }
  backend_policy_file="$output_dir/backend-role-policy.json"
  jq -n \
    --arg bucket "$(jq -er '.bucket' "$bootstrap_output")" \
    --arg table "$(jq -er '.dynamodb_table' "$bootstrap_output")" \
    --arg kms "$(jq -er '.kms_key_id' "$bootstrap_output")" \
    --arg region "$region" --arg account "$account" \
    '{Version:"2012-10-17",Statement:[
      {Sid:"StateBucket",Effect:"Allow",Action:["s3:ListBucket"],Resource:("arn:aws:s3:::" + $bucket)},
      {Sid:"StateObjects",Effect:"Allow",Action:["s3:GetObject","s3:PutObject","s3:DeleteObject"],Resource:("arn:aws:s3:::" + $bucket + "/*")},
      {Sid:"StateLock",Effect:"Allow",Action:["dynamodb:DescribeTable","dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem","dynamodb:UpdateItem"],Resource:("arn:aws:dynamodb:" + $region + ":" + $account + ":table/" + $table)},
      {Sid:"StateKey",Effect:"Allow",Action:["kms:Decrypt","kms:Encrypt","kms:ReEncrypt*","kms:GenerateDataKey","kms:DescribeKey"],Resource:$kms}
    ]}' > "$backend_policy_file"
  aws iam put-role-policy --role-name "$backend_role_name" --policy-name NodeOperatorBootstrapStateAccess --policy-document "file://$backend_policy_file"
  rm -f "$backend_policy_file"
  printf '%s\n' 'Bound least-privilege state access to the newly created backend role.' >&2
fi

# A fresh account has empty private mirrors. Copy only the exact, release-
# approved source digest after Terraform has created the destination ECR
# repositories, then read the destination digest back before proceeding.
if [ "${#bootstrap_mirror_images[@]}" -gt 0 ]; then
  [ -f "$platform_approval" ] || { printf '%s\n' 'release bundle lacks platform artifact approval for automatic mirroring' >&2; exit 65; }
  command -v docker >/dev/null 2>&1 || { printf '%s\n' 'docker is required to mirror missing approved bootstrap artifacts' >&2; exit 69; }
  registry="${account}.dkr.ecr.${region}.amazonaws.com"
  docker_config="$(mktemp -d "$output_dir/.docker-config.XXXXXX")"
  chmod 700 "$docker_config"
  trap 'unset confirmation validator_key expected_key withdrawal web3signer_image postgres_image prysm_image fence_image ecr_auth source_image; rm -f "$output_dir/.interactive-inputs.tmp" 2>/dev/null || true; rm -rf "$docker_config" 2>/dev/null || true' EXIT
  ecr_auth="$(aws ecr get-login-password --region "$region")"
  printf '%s' "$ecr_auth" | DOCKER_CONFIG="$docker_config" docker login --username AWS --password-stdin "$registry" >/dev/null
  for destination in "${bootstrap_mirror_images[@]}"; do
    case "$destination" in
      *node-operator-baseline-gitops-argocd@*) key=argocd_bootstrap ;;
      *node-operator-baseline-gitops-vault@*) key=vault_bootstrap ;;
      *) printf 'unrecognized bootstrap destination: %s\n' "$destination" >&2; exit 65 ;;
    esac
    source_image="$(jq -er --arg key "$key" '.artifacts[$key].source' "$platform_approval")"
    digest="${destination##*@}"; repository="${destination#*/}"; repository="${repository%@*}"
    aws ecr describe-repositories --region "$region" --repository-names "$repository" >/dev/null 2>&1 || \
      aws ecr create-repository --region "$region" --repository-name "$repository" >/dev/null
    DOCKER_CONFIG="$docker_config" docker pull "$source_image" >/dev/null
    DOCKER_CONFIG="$docker_config" docker tag "$source_image" "$registry/$repository:${digest#sha256:}"
    DOCKER_CONFIG="$docker_config" docker push "$registry/$repository:${digest#sha256:}" >/dev/null
    mirrored="$(aws ecr describe-images --region "$region" --repository-name "$repository" --image-ids imageTag="${digest#sha256:}" --query 'imageDetails[0].imageDigest' --output text)"
    [ "$mirrored" = "$digest" ] || { printf 'mirrored bootstrap digest mismatch: expected %s got %s\n' "$digest" "$mirrored" >&2; exit 65; }
  done
fi

step 'Publishing platform artifacts and bootstrapping GitOps/Vault'
platform_script="$source_root/scripts/release/run-platform-bootstrap.sh"
[ -x "$platform_script" ] || { printf '%s\n' 'release bundle lacks the unified platform bootstrap helper' >&2; exit 65; }
client_chart_version="$DEFAULT_CLIENT_CHART_VERSION"
client_chart_digest="$DEFAULT_CLIENT_CHART_DIGEST"
if [ -z "$client_chart_version" ] || [ -z "$client_chart_digest" ]; then
  source_chart_digest="$(aws ecr describe-images --region "$DEFAULT_CLIENT_CHART_SOURCE_REGION" --repository-name node-operator-baseline-gitops-client/node-operator-client --image-ids imageTag=0.1.37 --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
  if [[ "$source_chart_digest" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    client_chart_version="${client_chart_version:-0.1.37}"
    client_chart_digest="${client_chart_digest:-$source_chart_digest}"
    printf 'Using verified chart from %s: %s@%s\n' "$DEFAULT_CLIENT_CHART_SOURCE_REGION" "$client_chart_version" "$client_chart_digest" >&2
  fi
fi
client_chart_version="${client_chart_version:-$(prompt 'Published node-operator-client chart version (0.1.N)')}"
client_chart_digest="${client_chart_digest:-$(prompt 'Published node-operator-client chart manifest digest (sha256:...)')}"
zero_inputs="$(jq -er '.zero_resource_inputs' "$inputs")"
baseline_config="$(jq -er '.baseline_config' "$zero_inputs")"
platform_subnets=()
while IFS= read -r subnet; do [ -n "$subnet" ] && platform_subnets+=("$subnet"); done < <(jq -er '.hoodi_subnet_ids[]' "$output_dir/deployment-work/foundation-output.json")
[ "${#platform_subnets[@]}" -gt 0 ] || { printf '%s\n' 'foundation output lacks Hoodi private subnets for platform bootstrap' >&2; exit 65; }
platform_args=(--baseline-work-dir "$output_dir/deployment-work" --baseline-config "$baseline_config" --account "$account" --region "$region" --argocd-image "$argocd_bootstrap_image" --vault-image "$vault_bootstrap_image" --client-chart-version "$client_chart_version" --client-chart-digest "$client_chart_digest" --vault-chart-version "$DEFAULT_VAULT_CHART_VERSION" --vault-chart-digest "$DEFAULT_VAULT_CHART_DIGEST")
for subnet in "${platform_subnets[@]}"; do platform_args+=(--subnet-id "$subnet"); done
client_repository="$(terraform -chdir="$output_dir/deployment-work/baseline" output -raw gitops_client_ecr_repository_url 2>/dev/null || true)"
case "$client_repository" in
  "${account}.dkr.ecr.${region}.amazonaws.com/"*) ;;
  *) printf '%s\n' 'baseline did not expose the private client-chart ECR repository' >&2; exit 65 ;;
esac
client_repository="${client_repository#*/}"
client_found="$(aws ecr describe-images --region "$region" --repository-name "$client_repository" --image-ids imageTag="$client_chart_version" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
[ "$client_found" = "$client_chart_digest" ] || { printf 'client chart %s with digest %s is missing from private ECR\n' "$client_chart_version" "$client_chart_digest" >&2; printf '%s\n' 'Publish or mirror the reviewed immutable client chart, then rerun the single installer.' >&2; exit 65; }
"$platform_script" "${platform_args[@]}"

step 'Configuring private Vault TLS'
printf '%s\n' 'Preparing cert-manager-managed Vault TLS through the private EKS session.' >&2
eks_env=(env PRIVATE_EKS_SESSION=1 AWS_REGION="$region" EKS_CLUSTER_NAME="$(jq -er '.cluster_name' "$session")" SSM_OPS_INSTANCE_ID="$(jq -er '.ssm_ops_instance_id' "$session")")
tls_manifest="$source_root/docs/gitops/vault-tls-internal-ca.example.yaml"
[ -f "$tls_manifest" ] && [ ! -L "$tls_manifest" ] || { printf '%s\n' 'release bundle lacks the reviewed Vault TLS manifest' >&2; exit 65; }
"$source_root/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$vault_tls" --manifest "$tls_manifest"

step 'Running Vault v2 recovery and validator custody'
printf '%s\n' 'Next ceremony: Vault v2 recovery. Recovery shares will be requested silently by the delegated script.' >&2
"$bundle_root/source/scripts/ops/recover-and-bootstrap-hoodi-vault-v2.sh" --validator-set "$validator_set"

"$release" custody apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --keystore-dir "$keystore_dir_for_custody" --ceremony-dir "$output_dir/ceremony"

step 'Collecting signer and Beacon evidence'
mkdir -m 700 "$output_dir/evidence"
"$release" evidence signer --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --output-dir "$output_dir/evidence/signer"
"$release" evidence beacon --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --output-dir "$output_dir/evidence/beacon"

printf 'Generated and validated deposit attestation: %s\n' "$deposit_attestation" >&2
printf '%s\n' 'Activation requires independently reviewed public deposit, private Beacon, and signer evidence. Enter paths only; secret material is not accepted.' >&2
step 'Guarded validator activation'
public_deposit="$(prompt 'Absolute public deposit verification JSON')"
private_evidence="$(prompt 'Absolute private Beacon evidence JSON')"
signer_evidence="$(prompt 'Absolute signer evidence JSON')"
confirm_key="$(prompt 'Confirm validator public key (0x...)')"
confirm_withdrawal="$(prompt 'Confirm withdrawal address (0x...)')"
"$release" activate apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session" --deposit-attestation "$deposit_attestation" --public-deposit-verification "$public_deposit" --private-evidence "$private_evidence" --signer-evidence "$signer_evidence" --confirm-public-key "$confirm_key" --confirm-withdrawal-address "$confirm_withdrawal"
printf 'PASS: v0.1.20 interactive Hoodi release completed. Non-secret handoffs and evidence are under %s.\n' "$output_dir"
