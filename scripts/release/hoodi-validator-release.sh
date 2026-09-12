#!/usr/bin/env bash
set -euo pipefail
umask 077

# Drives only non-secret release boundaries from the single preparation
# handoff. Vault recovery, custody, GitOps publication, and activation remain
# separate ceremonies and cannot be smuggled through this entrypoint.
usage() {
  cat >&2 <<'USAGE'
usage:
  hoodi-validator-release.sh verify --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json
  hoodi-validator-release.sh interactive prepare --bundle-root DIRECTORY --output-dir /new-absolute-directory [--aws-region ap-northeast-1|ap-northeast-2]
  hoodi-validator-release.sh interactive deploy --bundle-root DIRECTORY --output-dir /new-absolute-directory [--aws-region ap-northeast-1|ap-northeast-2]
  hoodi-validator-release.sh interactive custody --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json --custody-dir /new-absolute/local-custody-directory
  hoodi-validator-release.sh infrastructure apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --work-dir /new-absolute-directory
  hoodi-validator-release.sh deploy apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --work-dir /new-absolute-directory --private-eks-session-handoff /new-absolute/session.json --allow-create
  hoodi-validator-release.sh custody apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json --keystore-dir /absolute/local-custody-directory --ceremony-dir /new-absolute/local-ceremony-directory
  hoodi-validator-release.sh evidence signer --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json --output-dir /absolute/nonsecret-evidence-directory
  hoodi-validator-release.sh evidence beacon --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json --output-dir /absolute/nonsecret-evidence-directory
  hoodi-validator-release.sh activate apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json --deposit-attestation /absolute/file.json --public-deposit-verification /absolute/file.json --private-evidence /absolute/file.json --signer-evidence /absolute/file.json --confirm-public-key 0x... --confirm-withdrawal-address 0x...
  hoodi-validator-release.sh ops-inputs prepare --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --zero-work-dir /absolute/zero-work-dir --output-dir /new-absolute-directory
  hoodi-validator-release.sh ops-access plan|apply --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --ops-inputs /absolute/ops-access-inputs.json --plan-file /absolute/private.tfplan [--expected-sha SHA256] [--allow-create] [--private-eks-session-handoff /absolute/session.json]
  hoodi-validator-release.sh stage plan|apply|verify --bundle-root DIRECTORY --inputs /absolute/hoodi-zero-release-inputs.json --private-eks-session-handoff /absolute/session.json
USAGE
  exit 64
}

command_name="${1:-}"; [ -n "$command_name" ] || usage
shift
operation=''; bundle_root=''; inputs=''; work_dir=''; session_handoff=''; output_dir=''; ops_inputs=''; plan_file=''; expected_sha=''; aws_region='ap-northeast-2'; allow_create=false; deposit_attestation=''; public_deposit_verification=''; private_evidence=''; signer_evidence=''; confirm_public_key=''; confirm_withdrawal_address=''; keystore_dir=''; ceremony_dir=''
case "$command_name" in
  interactive|infrastructure|deploy|custody|evidence|activate|ops-inputs|ops-access|stage)
    [ "$#" -gt 0 ] || usage
    operation="$1"
    shift
    ;;
  verify) ;;
  *) usage ;;
esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root) bundle_root="${2:-}"; shift 2 ;;
    --inputs) inputs="${2:-}"; shift 2 ;;
    --work-dir) work_dir="${2:-}"; shift 2 ;;
    --zero-work-dir) work_dir="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    --ops-inputs) ops_inputs="${2:-}"; shift 2 ;;
    --plan-file) plan_file="${2:-}"; shift 2 ;;
    --expected-sha) expected_sha="${2:-}"; shift 2 ;;
    --aws-region) aws_region="${2:-}"; shift 2 ;;
    --allow-create) allow_create=true; shift ;;
    --private-eks-session-handoff) session_handoff="${2:-}"; shift 2 ;;
    --deposit-attestation) deposit_attestation="${2:-}"; shift 2 ;;
    --public-deposit-verification) public_deposit_verification="${2:-}"; shift 2 ;;
    --private-evidence) private_evidence="${2:-}"; shift 2 ;;
    --signer-evidence) signer_evidence="${2:-}"; shift 2 ;;
    --confirm-public-key) confirm_public_key="${2:-}"; shift 2 ;;
    --confirm-withdrawal-address) confirm_withdrawal_address="${2:-}"; shift 2 ;;
    --keystore-dir) keystore_dir="${2:-}"; shift 2 ;;
    --ceremony-dir) ceremony_dir="${2:-}"; shift 2 ;;
    --custody-dir) ceremony_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [ "$command_name" = interactive ]; then
  [ "$operation" = prepare ] || [ "$operation" = deploy ] || [ "$operation" = custody ] || usage
  if [ "$operation" = custody ]; then
    [ -n "$bundle_root$inputs$session_handoff$ceremony_dir" ] && [ -z "$work_dir$output_dir$ops_inputs$plan_file$expected_sha$keystore_dir" ] && [ "$allow_create" = false ] || usage
    case "$bundle_root:$inputs:$session_handoff:$ceremony_dir" in /*:/*:/*:/*) ;; *) usage ;; esac
    [ -t 0 ] && [ -t 1 ] || { printf '%s\n' 'interactive custody requires a terminal' >&2; exit 69; }
    [ -d "$bundle_root/source" ] && [ -f "$bundle_root/bundle-manifest.json" ] || { printf '%s\n' 'bundle root is not a verified release layout' >&2; exit 65; }
    [ -f "$inputs" ] && [ ! -L "$inputs" ] && [ -f "$session_handoff" ] && [ ! -L "$session_handoff" ] || { printf '%s\n' 'interactive custody inputs must be regular files' >&2; exit 65; }
    [ ! -e "$ceremony_dir" ] && [ ! -L "$ceremony_dir" ] || { printf '%s\n' 'interactive custody directory must be new' >&2; exit 65; }
    command -v find >/dev/null 2>&1 || { printf '%s\n' 'missing command: find' >&2; exit 69; }
    input_parent="$(cd "$(dirname "$inputs")" && pwd -P)"
    validator_handoff="$input_parent/validator-deployment/validator-deployment-handoff.json"
    [ -f "$validator_handoff" ] && [ ! -L "$validator_handoff" ] || { printf '%s\n' 'interactive custody input lacks validator handoff' >&2; exit 65; }
    withdrawal_address="$(jq -er '.withdrawal_address | select(test("^0x[0-9a-fA-F]{40}$"))' "$validator_handoff")" || { printf '%s\n' 'interactive custody input lacks a valid withdrawal address' >&2; exit 65; }
    "$bundle_root/source/scripts/ops/generate-hoodi-validator-keystore.sh" --output-dir "$ceremony_dir"
    deposit_data="$(find "$ceremony_dir" -maxdepth 2 -type f -name 'deposit_data-*.json' -print)"
    [ "$(printf '%s\n' "$deposit_data" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || { printf '%s\n' 'key ceremony did not produce exactly one deposit-data file' >&2; exit 65; }
    "$bundle_root/source/scripts/ops/validate-hoodi-deposit-data.sh" --deposit-data "$deposit_data" --withdrawal-address "$withdrawal_address" --output-dir "$ceremony_dir/public-attestation"
    "$0" custody apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session_handoff" --keystore-dir "$ceremony_dir/validator_keys" --ceremony-dir "$ceremony_dir/public-ceremony"
    printf 'PASS: new local key custody is onboarded and public deposit attestation is ready at %s/public-attestation. Independently submit exactly one reviewed 32 HoodiETH deposit with your wallet before activation.\n' "$ceremony_dir"
    exit 0
  fi
  [ -n "$bundle_root$output_dir" ] && [ -z "$inputs$work_dir$session_handoff$ops_inputs$plan_file$expected_sha$keystore_dir$ceremony_dir" ] && [ "$allow_create" = false ] || usage
  case "$bundle_root:$output_dir" in */*:/*) ;; *) usage ;; esac
  [ -t 0 ] && [ -t 1 ] || { printf '%s\n' 'interactive preparation requires a terminal' >&2; exit 69; }
  command -v aws >/dev/null 2>&1 || { printf '%s\n' 'missing command: aws' >&2; exit 69; }
  case "$aws_region" in ap-northeast-1|ap-northeast-2) ;; *) printf '%s\n' 'aws region must be ap-northeast-1 or ap-northeast-2' >&2; exit 64 ;; esac
  identity="$(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN aws sts get-caller-identity --output json)"
  account="$(jq -er '.Account' <<<"$identity")"
  [[ "$account" =~ ^[0-9]{12}$ ]] || { printf '%s\n' 'current AWS identity did not return a valid account' >&2; exit 65; }
  prompt() { local label="$1" value; printf '%s: ' "$label" >&2; IFS= read -r value; printf '%s' "$value"; }
  validator_set="$(prompt 'Validator set (hoodi-...)')"
  validator_key="$(prompt 'Validator public key (0x...)')"
  withdrawal_address="$(prompt 'Withdrawal address (0x...)')"
  web3signer_image="$(prompt 'Approved Web3Signer private ECR digest')"
  postgres_image="$(prompt 'Approved PostgreSQL private ECR digest')"
  prysm_image="$(prompt 'Approved Prysm validator private ECR digest')"
  fence_image="$(prompt 'Approved signing-fence private ECR digest')"
  kubernetes_api_cidr="$(prompt 'Operator public IPv4 /32')"
  availability_zones=()
  while IFS= read -r zone; do availability_zones+=("$zone"); done < <(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN aws ec2 describe-availability-zones --region "$aws_region" --filters Name=state,Values=available --query 'AvailabilityZones[].ZoneName' --output text | tr '\t' '\n' | sort | head -n 2)
  [ "${#availability_zones[@]}" -eq 2 ] || { printf '%s\n' 'could not discover two available zones in the selected Region' >&2; exit 65; }
  backend_args=()
  identity_arn="$(jq -er '.Arn' <<<"$identity")"
  case "$identity_arn" in
    "arn:aws:iam::${account}:user/"*)
      backend_role="$(prompt 'Terraform backend IAM role ARN (same account)')"
      backend_args=(--backend-principal-arn "$backend_role")
      ;;
  esac
  "$bundle_root/source/scripts/release/prepare-hoodi-zero-release-inputs.sh" \
    --aws-account-id "$account" --aws-region "$aws_region" --availability-zone "${availability_zones[0]}" --availability-zone "${availability_zones[1]}" --validator-set "$validator_set" --validator-public-key "$validator_key" \
    --withdrawal-address "$withdrawal_address" --web3signer-image "$web3signer_image" \
    --postgres-image "$postgres_image" --prysm-validator-image "$prysm_image" \
    --signing-fence-image "$fence_image" --kubernetes-api-cidr "$kubernetes_api_cidr" --output-dir "$output_dir" "${backend_args[@]}"
  if [ "$operation" = deploy ]; then
    "$0" deploy apply --bundle-root "$bundle_root" --inputs "$output_dir/hoodi-zero-release-inputs.json" --work-dir "$output_dir/deployment-work" --private-eks-session-handoff "$output_dir/private-eks-session.json" --allow-create
    printf 'NEXT: run %s interactive custody --bundle-root %s --inputs %s/hoodi-zero-release-inputs.json --private-eks-session-handoff %s/private-eks-session.json --custody-dir /new-absolute/local-custody-directory\n' "${0##*/}" "$bundle_root" "$output_dir" "$output_dir"
  fi
  printf 'PASS: initial release values are prepared in %s.\n' "$output_dir"
  exit 0
fi

case "$bundle_root:$inputs" in */*:/*) ;; *) usage ;; esac
[ -d "$bundle_root/source" ] && [ -f "$bundle_root/bundle-manifest.json" ] || { printf '%s\n' 'bundle root is not a verified release layout' >&2; exit 65; }
[ -f "$inputs" ] && [ ! -L "$inputs" ] || { printf '%s\n' 'inputs must name a regular file' >&2; exit 65; }
command -v jq >/dev/null 2>&1 || { printf '%s\n' 'missing command: jq' >&2; exit 69; }

# Preserve the absolute path spelling recorded by the preparation handoff.
# macOS aliases /var to /private/var; canonicalizing here would make valid
# handoff references fail string equality even though the files are identical.
input_parent="$(dirname "$inputs")"
zero_inputs="$input_parent/zero-resource/zero-resource-inputs.json"
validator_handoff="$input_parent/validator-deployment/validator-deployment-handoff.json"
jq -e --arg zero "$zero_inputs" --arg validator "$validator_handoff" '
  .schema_version == 1 and .network == "hoodi" and
  (.aws_account_id | test("^[0-9]{12}$")) and
  (.validator_set | test("^hoodi-[a-z0-9][a-z0-9-]*$")) and
  (.aws_region | test("^ap-northeast-(1|2)$")) and .zero_resource_inputs == $zero and .validator_deployment_handoff == $validator and
  (.required_checkpoints | type == "array" and length == 6)
' "$inputs" >/dev/null || { printf '%s\n' 'inputs are not a bounded Hoodi zero-release contract' >&2; exit 65; }
[ -f "$zero_inputs" ] && [ ! -L "$zero_inputs" ] && [ -f "$validator_handoff" ] && [ ! -L "$validator_handoff" ] || { printf '%s\n' 'release contract references missing or unsafe inputs' >&2; exit 65; }
account="$(jq -er '.aws_account_id' "$inputs")"
input_region="$(jq -er '.aws_region' "$inputs")"
jq -e --arg account "$account" --arg region "$input_region" '.schema_version == 1 and .aws_account_id == $account and .aws_region == $region' "$zero_inputs" >/dev/null || { printf '%s\n' 'zero-resource input account or region does not match the release contract' >&2; exit 65; }
jq -e --arg account "$account" --arg region "$input_region" '.schema_version == 1 and .network == "hoodi" and .aws_account_id == $account and .aws_region == $region and .staged_client_replicas == 0 and .staged_fence_replicas == 0' "$validator_handoff" >/dev/null || { printf '%s\n' 'validator handoff does not match the release contract or is not fenced' >&2; exit 65; }

release_dir="$bundle_root/source/scripts/release"
"$release_dir/node-operator-release.sh" verify --bundle-root "$bundle_root"
case "$command_name" in
  verify)
    [ -z "$operation$work_dir$session_handoff" ] || usage
    printf 'PASS: Hoodi zero-release input contract is consistent and remains non-secret.\n'
    ;;
  infrastructure)
    [ "$operation" = apply ] && [ -n "$work_dir" ] && [ -z "$session_handoff$output_dir" ] || usage
    "$release_dir/node-operator-release.sh" zero apply --bundle-root "$bundle_root" --inputs "$zero_inputs" --work-dir "$work_dir"
    ;;
  deploy)
    [ "$operation" = apply ] && [ -n "$work_dir$session_handoff" ] && [ -z "$output_dir$ops_inputs$plan_file$expected_sha" ] && [ "$allow_create" = true ] || usage
    case "$work_dir:$session_handoff" in /*:/*) ;; *) usage ;; esac
    # Vault, custody, GitOps publication, deposit, and validator activation
    # remain separate operator ceremonies. Non-secret workload staging is safe
    # to continue once private EKS access has been established.
    "$0" infrastructure apply --bundle-root "$bundle_root" --inputs "$inputs" --work-dir "$work_dir"
    deploy_ops_dir="$work_dir/ops-access-inputs"
    deploy_ops_inputs="$deploy_ops_dir/ops-access-inputs.json"
    deploy_plan="$work_dir/ops-access.tfplan"
    if [ ! -f "$deploy_ops_inputs" ]; then
      [ ! -e "$deploy_ops_dir" ] || { printf '%s\n' 'deploy checkpoint contains an unsafe or incomplete ops-access input directory' >&2; exit 65; }
      "$0" ops-inputs prepare --bundle-root "$bundle_root" --inputs "$inputs" --zero-work-dir "$work_dir" --output-dir "$deploy_ops_dir"
    fi
    if [ ! -f "$deploy_plan" ]; then
      "$0" ops-access plan --bundle-root "$bundle_root" --inputs "$inputs" --ops-inputs "$deploy_ops_inputs" --plan-file "$deploy_plan" --allow-create
    fi
    deploy_sha="$(shasum -a 256 "$deploy_plan" | awk '{print $1}')"
    [[ "$deploy_sha" =~ ^[0-9a-f]{64}$ ]] || { printf '%s\n' 'deploy checkpoint contains an invalid ops-access plan digest' >&2; exit 65; }
    if [ -e "$session_handoff" ]; then
      [ -f "$session_handoff" ] && [ ! -L "$session_handoff" ] || { printf '%s\n' 'deploy checkpoint contains an unsafe private EKS session handoff' >&2; exit 65; }
      jq -e --arg region "$input_region" '
        .schema_version == 1 and .aws_region == $region and
        (.cluster_name | test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")) and
        (.ssm_ops_instance_id | test("^i-[0-9a-f]+$"))
      ' "$session_handoff" >/dev/null || { printf '%s\n' 'deploy checkpoint has an invalid private EKS session handoff' >&2; exit 65; }
    else
      "$0" ops-access apply --bundle-root "$bundle_root" --inputs "$inputs" --ops-inputs "$deploy_ops_inputs" --plan-file "$deploy_plan" --expected-sha "$deploy_sha" --allow-create --private-eks-session-handoff "$session_handoff"
    fi
    # The fence egress policy targets the private EKS API endpoint, whose
    # address is not knowable before foundation creation. Replace the bounded
    # preparation sentinel only after the private cluster and session handoff
    # exist, and fail closed if DNS does not yield exactly one IPv4 address.
    command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'missing command: python3 (required to resolve the private EKS endpoint)' >&2; exit 69; }
    client_manifest="$(jq -er '.client_manifest | select(type == "string" and startswith("/"))' "$validator_handoff")"
    endpoint_url="$(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN aws eks describe-cluster --region "$input_region" --name "$(jq -er '.cluster_name' "$session_handoff")" --query 'cluster.endpoint' --output text)"
    endpoint_host="${endpoint_url#https://}"; endpoint_host="${endpoint_host%%/*}"
    endpoint_ips="$(python3 - "$endpoint_host" <<'PY'
import socket, sys
host = sys.argv[1]
seen = []
for item in socket.getaddrinfo(host, 443, socket.AF_INET, socket.SOCK_STREAM):
    address = item[4][0]
    if address not in seen:
        seen.append(address)
print("\n".join(seen))
PY
)"
    [ -n "$endpoint_ips" ] || { printf '%s\n' 'private EKS endpoint did not resolve to an IPv4 address' >&2; exit 65; }
    if grep -q '127\.0\.0\.1/32' "$client_manifest"; then
      rewritten_manifest="$(mktemp "${client_manifest}.endpoint.XXXXXX")"
      python3 - "$client_manifest" "$rewritten_manifest" "$endpoint_ips" <<'PY'
import sys
source, target, raw_ips = sys.argv[1:]
ips = [ip.strip() for ip in raw_ips.splitlines() if ip.strip()]
if not ips or any(not all(part.isdigit() and 0 <= int(part) <= 255 for part in ip.split('.')) or len(ip.split('.')) != 4 for ip in ips):
    raise SystemExit("invalid private EKS endpoint address")
with open(source, encoding="utf-8") as handle:
    lines = handle.readlines()
with open(target, "w", encoding="utf-8") as handle:
    for line in lines:
        if "cidr: 127.0.0.1/32" in line:
            indent = line[:len(line) - len(line.lstrip())]
            for ip in ips:
                handle.write(f"{indent}- to: [{{ipBlock: {{cidr: {ip}/32}}}}]\n")
        else:
            handle.write(line)
PY
      chmod 600 "$rewritten_manifest"
      mv "$rewritten_manifest" "$client_manifest"
      printf 'Resolved private EKS API endpoint %s; validator fence policy narrowed to %s.\n' "$endpoint_host" "$(printf '%s' "$endpoint_ips" | tr '\n' ' ')" >&2
    else
      printf 'Validator fence policy is already narrowed; reusing the existing endpoint-bound manifest.\n' >&2
    fi
    # Retry only an exact zero-replica boundary. A wholly absent set may be
    # staged; a partial or active set fails closed rather than being adopted.
    if "$0" stage verify --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session_handoff"; then
      :
    else
      stage_status=$?
      [ "$stage_status" -eq 3 ] || exit "$stage_status"
      "$0" stage apply --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session_handoff"
      "$0" stage verify --bundle-root "$bundle_root" --inputs "$inputs" --private-eks-session-handoff "$session_handoff"
    fi
    printf 'PASS: infrastructure, isolated private-EKS SSM access, and zero-replica validator staging are deployed. Continue with the separate Vault, custody, GitOps, deposit, and validator activation ceremonies.\n'
    ;;
  custody)
    [ "$operation" = apply ] && [ -n "$session_handoff$keystore_dir$ceremony_dir" ] && [ -z "$work_dir$output_dir$ops_inputs$plan_file$expected_sha$deposit_attestation$public_deposit_verification$private_evidence$signer_evidence$confirm_public_key$confirm_withdrawal_address" ] || usage
    case "$session_handoff:$keystore_dir:$ceremony_dir" in /*:/*:/*) ;; *) usage ;; esac
    [ -f "$session_handoff" ] && [ ! -L "$session_handoff" ] || { printf '%s\n' 'custody session handoff must be a regular file' >&2; exit 65; }
    [ -d "$keystore_dir" ] && [ ! -L "$keystore_dir" ] || { printf '%s\n' 'custody keystore directory must be a real local directory' >&2; exit 65; }
    [ ! -e "$ceremony_dir" ] && [ ! -L "$ceremony_dir" ] || { printf '%s\n' 'custody ceremony directory must be new so public CA evidence cannot be overwritten' >&2; exit 65; }
    session_region="$(jq -er 'select(.schema_version == 1 and (.aws_region | test("^ap-northeast-(1|2)$")) and (.cluster_name | test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")) and (.ssm_ops_instance_id | test("^i-[0-9a-f]+$"))) | .aws_region' "$session_handoff")" || { printf '%s\n' 'custody session handoff is invalid' >&2; exit 65; }
    session_cluster="$(jq -er '.cluster_name' "$session_handoff")"; session_instance="$(jq -er '.ssm_ops_instance_id' "$session_handoff")"
    [ "$session_region" = "$input_region" ] || { printf '%s\n' 'custody session points to another Region' >&2; exit 65; }
    validator_set="$(jq -er '.validator_set' "$validator_handoff")"
    mkdir -m 700 "$ceremony_dir"
    eks_env=(env AWS_REGION="$session_region" EKS_CLUSTER_NAME="$session_cluster" SSM_OPS_INSTANCE_ID="$session_instance")
    "$bundle_root/source/scripts/ops/with-private-vault.sh" -- "${eks_env[@]}" PRIVATE_VAULT_SESSION=1 "$bundle_root/source/scripts/ops/recover-and-bootstrap-hoodi-validator-runtime-vault.sh" --validator-set "$validator_set"
    "$bundle_root/source/scripts/ops/with-private-vault.sh" -- "${eks_env[@]}" PRIVATE_VAULT_SESSION=1 "$bundle_root/source/scripts/ops/recover-and-onboard-hoodi-validator-keystore.sh" --validator-set "$validator_set" --keystore-dir "$keystore_dir" --signer-ca-output "$ceremony_dir/signer-ca.crt" --known-clients-output "$ceremony_dir/known-clients.txt"
    "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" PRIVATE_EKS_SESSION=1 kubectl -n validator-operations create configmap "validator-${validator_set}-known-clients" --from-file="known-clients=$ceremony_dir/known-clients.txt" --dry-run=client -o yaml | "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" PRIVATE_EKS_SESSION=1 kubectl apply -f - >/dev/null
    printf 'PASS: Vault runtime, encrypted local custody onboarding, and transport TLS were configured. Public CA evidence is in %s; no validator workload was started.\n' "$ceremony_dir"
    ;;
  evidence)
    [ "$operation" = signer ] || [ "$operation" = beacon ] || usage
    [ -n "$session_handoff$output_dir" ] && [ -z "$work_dir$ops_inputs$plan_file$expected_sha$keystore_dir$ceremony_dir$deposit_attestation$public_deposit_verification$private_evidence$signer_evidence$confirm_public_key$confirm_withdrawal_address" ] || usage
    case "$session_handoff:$output_dir" in /*:/*) ;; *) usage ;; esac
    [ -f "$session_handoff" ] && [ ! -L "$session_handoff" ] || { printf '%s\n' 'signer evidence session handoff must be a regular file' >&2; exit 65; }
    session_region="$(jq -er 'select(.schema_version == 1 and (.aws_region | test("^ap-northeast-(1|2)$")) and (.cluster_name | test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")) and (.ssm_ops_instance_id | test("^i-[0-9a-f]+$"))) | .aws_region' "$session_handoff")" || { printf '%s\n' 'signer evidence session handoff is invalid' >&2; exit 65; }
    session_cluster="$(jq -er '.cluster_name' "$session_handoff")"; session_instance="$(jq -er '.ssm_ops_instance_id' "$session_handoff")"
    [ "$session_region" = "$input_region" ] || { printf '%s\n' 'signer evidence session points to another Region' >&2; exit 65; }
    validator_set="$(jq -er '.validator_set' "$validator_handoff")"
    validator_key="$(jq -er '.validator_public_key | select(test("^0x[0-9a-fA-F]{96}$"))' "$validator_handoff")" || { printf '%s\n' 'validator handoff lacks a valid public key for signer evidence' >&2; exit 65; }
    eks_env=(env PRIVATE_EKS_SESSION=1 AWS_REGION="$session_region" EKS_CLUSTER_NAME="$session_cluster" SSM_OPS_INSTANCE_ID="$session_instance")
    if [ "$operation" = signer ]; then
      "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$bundle_root/source/scripts/ops/start-hoodi-validator-signer.sh" --validator-set "$validator_set"
      "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$bundle_root/source/scripts/ops/collect-hoodi-signer-public-key-evidence.sh" --validator-set "$validator_set" --validator-public-key "$validator_key" --output-dir "$output_dir"
      printf 'PASS: signer is running at one replica and fresh TLS public-key evidence was collected in %s. Wait for matching public deposit and private Beacon active evidence before activation.\n' "$output_dir"
    else
      command -v uuidgen >/dev/null 2>&1 || { printf '%s\n' 'missing command: uuidgen' >&2; exit 69; }
      correlation_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
      "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$bundle_root/source/scripts/ops/observe-private-hoodi-validator.sh" --validator-set "$validator_set" --validator-public-key "$validator_key" --correlation-id "$correlation_id" --output-dir "$output_dir"
      printf 'PASS: fresh private Beacon evidence was collected in %s. It must show synced and active_ongoing before activation.\n' "$output_dir"
    fi
    ;;
  activate)
    [ "$operation" = apply ] && [ -n "$session_handoff$deposit_attestation$public_deposit_verification$private_evidence$signer_evidence$confirm_public_key$confirm_withdrawal_address" ] && [ -z "$work_dir$output_dir$ops_inputs$plan_file$expected_sha" ] || usage
    for evidence in "$session_handoff" "$deposit_attestation" "$public_deposit_verification" "$private_evidence" "$signer_evidence"; do case "$evidence" in /*) ;; *) usage ;; esac; [ -f "$evidence" ] && [ ! -L "$evidence" ] || { printf '%s\n' 'activation input must be a regular file' >&2; exit 65; }; done
    session_region="$(jq -er '
      select(
        .schema_version == 1 and
        (.aws_region | test("^ap-northeast-(1|2)$")) and
        (.cluster_name | test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")) and
        (.ssm_ops_instance_id | test("^i-[0-9a-f]+$"))
      ) | .aws_region
    ' "$session_handoff")" || { printf '%s\n' 'activation session handoff is invalid' >&2; exit 65; }
    session_cluster="$(jq -er '.cluster_name' "$session_handoff")"; session_instance="$(jq -er '.ssm_ops_instance_id' "$session_handoff")"
    [ "$session_region" = "$input_region" ] || { printf '%s\n' 'activation session points to another Region' >&2; exit 65; }
    validator_set="$(jq -er '.validator_set' "$validator_handoff")"
    eks_env=(env PRIVATE_EKS_SESSION=1 AWS_REGION="$session_region" EKS_CLUSTER_NAME="$session_cluster" SSM_OPS_INSTANCE_ID="$session_instance")
    "$bundle_root/source/scripts/ops/with-private-eks.sh" -- "${eks_env[@]}" "$bundle_root/source/scripts/ops/activate-hoodi-validator-client.sh" --validator-set "$validator_set" --deposit-attestation "$deposit_attestation" --public-deposit-verification "$public_deposit_verification" --private-evidence "$private_evidence" --signer-evidence "$signer_evidence" --confirm-public-key "$confirm_public_key" --confirm-withdrawal-address "$confirm_withdrawal_address"
    printf 'PASS: validator activation was submitted through the fixed session and guarded evidence path.\n'
    ;;
  ops-inputs)
    [ "$operation" = prepare ] && [ -n "$work_dir$output_dir" ] && [ -z "$session_handoff" ] || usage
    case "$work_dir:$output_dir" in /*:/*) ;; *) usage ;; esac
    "$release_dir/prepare-ops-access-inputs.sh" --handoff "$work_dir/ops-access-handoff.json" --output-dir "$output_dir"
    ;;
  ops-access)
    [ "$operation" = plan ] || [ "$operation" = apply ] || usage
    case "$ops_inputs:$plan_file" in /*:/*) ;; *) usage ;; esac
    if [ "$operation" = apply ]; then
      [ -n "$session_handoff" ] || { printf '%s\n' 'ops-access apply must write --private-eks-session-handoff for the next release phase' >&2; exit 64; }
    else
      [ -z "$session_handoff" ] || { printf '%s\n' 'ops-access plan must not create a private EKS session handoff' >&2; exit 64; }
    fi
    [ -f "$ops_inputs" ] && [ ! -L "$ops_inputs" ] || { printf '%s\n' 'ops inputs must be a regular file' >&2; exit 65; }
    ops_parent="$(cd "$(dirname "$ops_inputs")" && pwd -P)"
    ops_handoff="$(jq -er '.ops_access_handoff' "$ops_inputs")" || { printf '%s\n' 'ops inputs lack a source handoff' >&2; exit 65; }
    [ -f "$ops_handoff" ] && [ ! -L "$ops_handoff" ] || { printf '%s\n' 'ops source handoff is unsafe' >&2; exit 65; }
    jq -e --arg account "$account" --arg handoff "$ops_handoff" --arg config "$ops_parent/ops-access.tfvars.json" --arg backend "$ops_parent/ops-access.backend.hcl" '
      .schema_version == 1 and .ops_access_handoff == $handoff and .config == $config and .backend_config == $backend
    ' "$ops_inputs" >/dev/null || { printf '%s\n' 'ops input paths are not bounded' >&2; exit 65; }
    jq -e --arg account "$account" '.schema_version == "v1" and .aws_account_id == $account' "$ops_handoff" >/dev/null || { printf '%s\n' 'ops access account does not match the release contract' >&2; exit 65; }
    ops_args=("$operation" --root "$bundle_root/source" --inputs "$ops_inputs" --plan-file "$plan_file")
    [ -z "$expected_sha" ] || ops_args+=(--expected-sha "$expected_sha")
    [ "$allow_create" = false ] || ops_args+=(--allow-create)
    [ -z "$session_handoff" ] || ops_args+=(--session-handoff "$session_handoff")
    "$release_dir/node-operator-ops-access.sh" "${ops_args[@]}"
    ;;
  stage)
    [ "$operation" = plan ] || [ "$operation" = apply ] || [ "$operation" = verify ] || usage
    [ -n "$session_handoff" ] && [ -z "$work_dir$output_dir" ] || usage
    "$release_dir/stage-hoodi-validator-deployment.sh" "$operation" --handoff "$validator_handoff" --private-eks-session-handoff "$session_handoff"
    ;;
esac
