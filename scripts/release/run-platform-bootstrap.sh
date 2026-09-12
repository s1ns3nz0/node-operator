#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  printf '%s\n' "usage: ${0##*/} --baseline-work-dir ABSOLUTE_DIR --baseline-config ABSOLUTE_FILE --account ACCOUNT --region REGION --argocd-image IMAGE@DIGEST --vault-image IMAGE@DIGEST --client-chart-version 0.1.N --client-chart-digest sha256:DIGEST --vault-chart-version VERSION --vault-chart-digest sha256:DIGEST --subnet-id subnet-ID [--subnet-id subnet-ID]"
  exit 64
}

work_dir=''; baseline_config=''; account=''; region=''; argocd_image=''; vault_image=''; client_version=''; client_digest=''; vault_version=''; vault_digest=''; subnets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --baseline-work-dir) work_dir="${2:-}"; shift 2 ;;
    --baseline-config) baseline_config="${2:-}"; shift 2 ;;
    --account) account="${2:-}"; shift 2 ;;
    --region) region="${2:-}"; shift 2 ;;
    --argocd-image) argocd_image="${2:-}"; shift 2 ;;
    --vault-image) vault_image="${2:-}"; shift 2 ;;
    --client-chart-version) client_version="${2:-}"; shift 2 ;;
    --client-chart-digest) client_digest="${2:-}"; shift 2 ;;
    --vault-chart-version) vault_version="${2:-}"; shift 2 ;;
    --vault-chart-digest) vault_digest="${2:-}"; shift 2 ;;
    --subnet-id) subnets+=("${2:-}"); shift 2 ;;
    *) usage ;;
  esac
done
case "$work_dir:$baseline_config:$account:$region:$argocd_image:$vault_image:$client_version:$client_digest:$vault_version:$vault_digest" in /*:/*:*:*:*:*:*:*:*:*:*) ;; *) usage ;; esac
[[ "$account" =~ ^[0-9]{12}$ ]] || usage
[[ "$region" =~ ^ap-northeast-(1|2)$ ]] || usage
[[ "$argocd_image" =~ ^${account}\.dkr\.ecr\.${region}\.amazonaws\.com/.+@sha256:[a-f0-9]{64}$ ]] || usage
[[ "$vault_image" =~ ^${account}\.dkr\.ecr\.${region}\.amazonaws\.com/.+@sha256:[a-f0-9]{64}$ ]] || usage
[[ "$client_version" =~ ^0\.1\.[0-9]+$ && "$client_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || usage
[[ "$vault_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$vault_digest" =~ ^sha256:[a-f0-9]{64}$ ]] || usage
[ "${#subnets[@]}" -gt 0 ] || usage
for subnet in "${subnets[@]}"; do [[ "$subnet" =~ ^subnet-[a-z0-9]+$ ]] || usage; done
for command in terraform jq aws; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
platform_stage_number=0
platform_stage() {
  platform_stage_number=$((platform_stage_number + 1))
  printf '\n▶ PLATFORM %02d/06  %s\n' "$platform_stage_number" "$1" >&2
}
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ -d "$work_dir/baseline" ] && [ -f "$work_dir/baseline.backend.hcl" ] || { printf '%s\n' 'baseline work directory is not a zero-apply result' >&2; exit 65; }
[ -f "$baseline_config" ] && [ ! -L "$baseline_config" ] || { printf '%s\n' 'baseline config must be a regular file' >&2; exit 65; }

input_dir="$work_dir/platform-bootstrap-inputs"; mkdir -m 700 "$input_dir" 2>/dev/null || { [ -d "$input_dir" ] || exit 65; }
argocd_input="$input_dir/argocd.tfvars.json"; vault_input="$input_dir/vault.tfvars.json"
subnet_json="$(printf '%s\n' "${subnets[@]}" | jq -R . | jq -s .)"
jq -n --arg image "$argocd_image" --arg version "$client_version" --arg digest "$client_digest" --argjson subnets "$subnet_json" \
  '{enable_argocd_bootstrap_runner:true,enable_argocd_bootstrap_cluster_admin:true,argocd_bootstrap_image:$image,argocd_bootstrap_subnet_ids:$subnets,gitops_client_chart_version:$version,gitops_client_chart_oci_digest:$digest}' > "$argocd_input"
jq -n --arg image "$vault_image" --arg version "$vault_version" --arg digest "$vault_digest" --argjson subnets "$subnet_json" \
  '{enable_vault_bootstrap_runner:true,enable_vault_bootstrap_cluster_admin:true,vault_bootstrap_image:$image,vault_bootstrap_subnet_ids:$subnets,vault_chart_version:$version,vault_chart_manifest_digest:$digest}' > "$vault_input"
chmod 600 "$argocd_input" "$vault_input"

platform_dir="$work_dir/platform-bootstrap-plans"; mkdir -m 700 "$platform_dir" 2>/dev/null || { [ -d "$platform_dir" ] || exit 65; }
argocd_plan="$platform_dir/argocd.tfplan"; vault_plan="$platform_dir/vault.tfplan"
if [ ! -f "$argocd_plan" ]; then
  platform_stage 'Planning Argo CD bootstrap runner'
  "$script_dir/apply-argocd-bootstrap.sh" plan --baseline-work-dir "$work_dir" --baseline-config "$baseline_config" --bootstrap-input "$argocd_input" --plan-file "$argocd_plan"
fi
platform_stage 'Awaiting explicit Argo/Vault bootstrap approval'
printf 'Type PLATFORM-BOOTSTRAP to apply the reviewed Argo/Vault runner plans: ' >&2
IFS= read -r confirmation
[ "$confirmation" = PLATFORM-BOOTSTRAP ] || { printf '%s\n' 'platform bootstrap cancelled' >&2; exit 0; }
platform_stage 'Applying Argo CD bootstrap runner'
"$script_dir/apply-argocd-bootstrap.sh" apply --baseline-work-dir "$work_dir" --baseline-config "$baseline_config" --bootstrap-input "$argocd_input" --plan-file "$argocd_plan"

# Argo apply changes the shared Terraform state. Generate the Vault plan only
# after that apply, and retain the Argo variables in its baseline overlay so
# Terraform does not plan to delete the already-applied Argo runner.
vault_baseline_config="$platform_dir/vault-baseline.tfvars.json"
jq -s '.[0] * .[1]' "$baseline_config" "$argocd_input" > "$vault_baseline_config"
chmod 600 "$vault_baseline_config"
if [ -f "$vault_plan" ]; then
  mv "$vault_plan" "$vault_plan.stale.$(date -u +%Y%m%dT%H%M%SZ)"
fi
platform_stage 'Planning Vault bootstrap runner'
"$script_dir/apply-vault-bootstrap.sh" plan --baseline-work-dir "$work_dir" --baseline-config "$vault_baseline_config" --bootstrap-input "$vault_input" --plan-file "$vault_plan"
platform_stage 'Applying Vault bootstrap runner'
"$script_dir/apply-vault-bootstrap.sh" apply --baseline-work-dir "$work_dir" --baseline-config "$baseline_config" --bootstrap-input "$vault_input" --plan-file "$vault_plan"

platform_stage 'Waiting for Argo/Vault CodeBuild completion'
for project in "$(terraform -chdir="$work_dir/baseline" output -raw argocd_bootstrap_project_name 2>/dev/null || true)" "$(terraform -chdir="$work_dir/baseline" output -raw vault_bootstrap_project_name 2>/dev/null || true)"; do
  [ -n "$project" ] || continue
  build_id="$(aws codebuild start-build --region "$region" --project-name "$project" --query 'build.id' --output text)"
  deadline=$((SECONDS + 1800))
  while :; do
    status="$(aws codebuild batch-get-builds --region "$region" --ids "$build_id" --query 'builds[0].buildStatus' --output text)"
    case "$status" in SUCCEEDED) break;; FAILED|FAULT|STOPPED|TIMED_OUT) printf 'CodeBuild %s ended with %s\n' "$project" "$status" >&2; exit 70;; esac
    [ "$SECONDS" -lt "$deadline" ] || { printf 'CodeBuild %s timed out\n' "$project" >&2; exit 70; }
    sleep 10
  done
done

# Remove the temporary runners and cluster-admin associations. The baseline
# configuration has all bootstrap flags disabled; only the explicitly named
# bootstrap resources may be deleted by this revoke plan.
platform_stage 'Revoking temporary runners and authority'
revoke_plan="$platform_dir/revoke.tfplan"
if [ ! -f "$revoke_plan" ]; then
  terraform -chdir="$work_dir/baseline" plan -input=false -var-file="$baseline_config" -out="$revoke_plan"
  terraform -chdir="$work_dir/baseline" show -json "$revoke_plan" | jq -e '
    all(.resource_changes[]?;
      (.change.actions | index("delete") | not) or
      (.address | test("^(aws_(codebuild_project|cloudwatch_log_group|eks_access_(entry|policy_association)|iam_role|iam_role_policy|security_group|vpc_security_group_(egress_rule|ingress_rule))\\.(argocd_bootstrap|vault_bootstrap|argocd_bootstrap_cluster_admin|vault_bootstrap_cluster_admin)|aws_vpc_endpoint\\.private|aws_vpc_security_group_egress_rule\\.endpoints_to_(argocd|vault)_bootstrap)(\\[[0-9]+\\])?$"))
    )
  ' >/dev/null || { printf '%s\n' 'revoke plan contains an unexpected deletion; refusing cleanup' >&2; exit 70; }
fi
terraform -chdir="$work_dir/baseline" apply -input=false "$revoke_plan"
printf '%s\n' 'PASS: Argo, cert-manager and Vault bootstrap runners completed; temporary authority and runners were revoked.'
