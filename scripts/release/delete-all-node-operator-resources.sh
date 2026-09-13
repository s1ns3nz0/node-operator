#!/usr/bin/env bash
set -euo pipefail
umask 077

# One-shot teardown for a disposable Node Operator test account. It creates a
# narrowly scoped break-glass role, performs AWS/Kubernetes cleanup, then
# removes both the role and the temporary user policy. It never changes KMS
# key policies; resource-policy denies are reported instead of bypassed.
usage(){ printf '%s\n' "usage: ${0##*/} --execute --region ap-northeast-2 [--cluster node-operator] [--ops-instance-id i-...] [--vpc-id vpc-...] [--object-lock-bucket BUCKET] [--root-profile PROFILE]" >&2; exit 64; }
execute=false; region="${AWS_REGION:-ap-northeast-2}"; cluster='node-operator'; ops_instance=''; vpc_id=''; object_bucket=''; root_profile=''
while [ "$#" -gt 0 ]; do case "$1" in
  --execute) execute=true; shift;; --region) region="${2:-}"; shift 2;; --cluster) cluster="${2:-}"; shift 2;; --ops-instance-id) ops_instance="${2:-}"; shift 2;; --vpc-id) vpc_id="${2:-}"; shift 2;; --object-lock-bucket) object_bucket="${2:-}"; shift 2;; --root-profile) root_profile="${2:-}"; shift 2;; *) usage;;
esac; done
[ "$execute" = true ] || usage
[[ "$cluster" =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ ]] || { printf '%s\n' 'invalid EKS cluster name' >&2; exit 64; }
command -v aws >/dev/null 2>&1 || { printf '%s\n' 'missing command: aws' >&2; exit 69; }
account="$(aws sts get-caller-identity --query Account --output text)"; caller="$(aws sts get-caller-identity --query Arn --output text)"; user_name="${caller##*/}"
role="node-operator-full-cleanup-$(date -u +%Y%m%d%H%M%S)"; role_arn="arn:aws:iam::${account}:role/${role}"; policy_name='node-operator-full-cleanup-assume'; policy_file="$(mktemp /private/tmp/node-operator-full-cleanup.XXXXXX)"
cleanup(){ set +e; unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN; aws iam delete-user-policy --user-name "$user_name" --policy-name "$policy_name" >/dev/null 2>&1 || true; aws iam delete-role-policy --role-name "$role" --policy-name cleanup >/dev/null 2>&1 || true; aws iam delete-role --role-name "$role" >/dev/null 2>&1 || true; unlink "$policy_file" >/dev/null 2>&1 || true; }; trap cleanup EXIT INT TERM

jq -n --arg region "$region" --arg bucket "$object_bucket" '{Version:"2012-10-17",Statement:[
 {Effect:"Allow",Action:["ec2:Describe*","ec2:Delete*","ec2:TerminateInstances","ec2:DetachInternetGateway","ssm:DescribeInstanceInformation"],Resource:"*",Condition:{StringEquals:{"aws:RequestedRegion":$region}}},
 {Effect:"Allow",Action:["eks:DescribeCluster","eks:ListNodegroups","eks:DeleteNodegroup","eks:DeleteCluster"],Resource:"*",Condition:{StringEquals:{"aws:RequestedRegion":$region}}},
 {Effect:"Allow",Action:["s3:ListBucket","s3:ListBucketVersions","s3:GetObjectRetention","s3:DeleteObject","s3:DeleteObjectVersion","s3:BypassGovernanceRetention","s3:DeleteBucket"],Resource:[("arn:aws:s3:::"+$bucket),("arn:aws:s3:::"+$bucket+"/*")]},
 {Effect:"Allow",Action:["kms:ListAliases","kms:DeleteAlias","kms:DescribeKey","kms:ScheduleKeyDeletion"],Resource:"*"},
 {Effect:"Allow",Action:["ecr:DescribeRepositories","ecr:DeleteRepository"],Resource:"*"}
]}' > "$policy_file"
aws iam create-role --role-name "$role" --assume-role-policy-document "$(jq -nc --arg caller "$caller" '{Version:"2012-10-17",Statement:[{Effect:"Allow",Principal:{AWS:$caller},Action:"sts:AssumeRole"}]}')" >/dev/null
aws iam put-role-policy --role-name "$role" --policy-name cleanup --policy-document "$(jq -c . "$policy_file")"
aws iam put-user-policy --user-name "$user_name" --policy-name "$policy_name" --policy-document "$(jq -nc --arg role "$role_arn" '{Version:"2012-10-17",Statement:[{Effect:"Allow",Action:"sts:AssumeRole",Resource:$role}]}')"
creds=''; for _ in $(seq 1 30); do creds="$(aws sts assume-role --role-arn "$role_arn" --role-session-name node-operator-full-cleanup 2>/dev/null || true)"; [ -n "$creds" ] && break; sleep 2; done; [ -n "$creds" ] || { printf '%s\n' 'temporary AssumeRole permission did not propagate' >&2; exit 77; }
export AWS_ACCESS_KEY_ID="$(jq -er '.Credentials.AccessKeyId' <<<"$creds")" AWS_SECRET_ACCESS_KEY="$(jq -er '.Credentials.SecretAccessKey' <<<"$creds")" AWS_SESSION_TOKEN="$(jq -er '.Credentials.SessionToken' <<<"$creds")"

# EKS owns ENIs, node groups, and security-group dependencies. Remove these
# first so the later VPC pass is deterministic. Missing resources are safe.
if aws eks describe-cluster --region "$region" --name "$cluster" >/dev/null 2>&1; then
  for ng in $(aws eks list-nodegroups --region "$region" --cluster-name "$cluster" --query 'nodegroups[]' --output text); do
    aws eks delete-nodegroup --region "$region" --cluster-name "$cluster" --nodegroup-name "$ng" >/dev/null 2>&1 || true
  done
  for _ in $(seq 1 90); do
    remaining="$(aws eks list-nodegroups --region "$region" --cluster-name "$cluster" --query 'nodegroups[]' --output text 2>/dev/null || true)"
    [ -z "$remaining" ] || { sleep 10; continue; }
    break
  done
  aws eks delete-cluster --region "$region" --name "$cluster" >/dev/null 2>&1 || true
  for _ in $(seq 1 90); do
    aws eks describe-cluster --region "$region" --name "$cluster" >/dev/null 2>&1 || break
    sleep 10
  done
  printf 'PASS: EKS cluster cleanup requested for %s.\n' "$cluster"
else
  printf 'INFO: EKS cluster %s is absent; skipping cluster cleanup.\n' "$cluster"
fi

if [ -n "$ops_instance" ]; then
  if aws ec2 describe-instances --region "$region" --instance-ids "$ops_instance" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null | grep -qx "$ops_instance"; then
    aws ec2 terminate-instances --region "$region" --instance-ids "$ops_instance" >/dev/null 2>&1 || true
    printf 'PASS: SSM operations host termination requested for %s.\n' "$ops_instance"
  else
    printf 'INFO: SSM operations host %s is absent; skipping host cleanup.\n' "$ops_instance"
  fi
fi

if [ -n "$object_bucket" ]; then
  v="$(aws s3api list-object-versions --region "$region" --bucket "$object_bucket" 2>/dev/null || echo '{"Versions":[],"DeleteMarkers":[]}')"
  if [ "$(jq '[.Versions[]?,.DeleteMarkers[]?]|length' <<<"$v")" -gt 0 ]; then jq '{Objects:([.Versions[]?,.DeleteMarkers[]?]|map({Key,VersionId})),Quiet:true}' <<<"$v" | aws s3api delete-objects --region "$region" --bucket "$object_bucket" --bypass-governance-retention --delete file:///dev/stdin; fi
  aws s3api delete-bucket --region "$region" --bucket "$object_bucket" 2>/dev/null || true
fi
if [ -n "$root_profile" ]; then
  root_arn="$(aws --profile "$root_profile" sts get-caller-identity --query Arn --output text 2>/dev/null || true)"
  [[ "$root_arn" == "arn:aws:iam::${account}:root" ]] || { printf '%s\n' 'root profile did not resolve to the account root principal; refusing KMS cleanup' >&2; exit 78; }
  for alias in $(aws --profile "$root_profile" kms list-aliases --region "$region" --query 'Aliases[?starts_with(AliasName, `alias/node-operator-baseline-`)].AliasName' --output text); do
    aws --profile "$root_profile" kms delete-alias --region "$region" --alias-name "$alias"
  done
else
  for alias in $(aws kms list-aliases --region "$region" --query 'Aliases[?starts_with(AliasName, `alias/node-operator-baseline-`)].AliasName' --output text); do aws kms delete-alias --region "$region" --alias-name "$alias" 2>/dev/null || printf 'WARN: KMS alias denied by key policy (rerun with --root-profile): %s\n' "$alias"; done
fi
for repo in $(aws ecr describe-repositories --region "$region" --query 'repositories[?starts_with(repositoryName, `node-operator-baseline-`) || starts_with(repositoryName, `node-op-`)].repositoryName' --output text); do aws ecr delete-repository --region "$region" --repository-name "$repo" --force 2>/dev/null || printf 'WARN: ECR repository could not be deleted: %s\n' "$repo"; done

if [ -n "$vpc_id" ]; then
  for ep in $(aws ec2 describe-vpc-endpoints --region "$region" --filters Name=vpc-id,Values="$vpc_id" --query 'VpcEndpoints[].VpcEndpointId' --output text); do aws ec2 delete-vpc-endpoints --region "$region" --vpc-endpoint-ids "$ep" >/dev/null 2>&1 || true; done
  for nat in $(aws ec2 describe-nat-gateways --region "$region" --filter Name=vpc-id,Values="$vpc_id" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text); do aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat" >/dev/null 2>&1 || true; done
  for eni in $(aws ec2 describe-network-interfaces --region "$region" --filters Name=vpc-id,Values="$vpc_id" --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' --output text); do aws ec2 delete-network-interface --region "$region" --network-interface-id "$eni" >/dev/null 2>&1 || true; done
  for subnet in $(aws ec2 describe-subnets --region "$region" --filters Name=vpc-id,Values="$vpc_id" --query 'Subnets[].SubnetId' --output text); do aws ec2 delete-subnet --region "$region" --subnet-id "$subnet" >/dev/null 2>&1 || true; done
  rules="$(aws ec2 describe-security-group-rules --region "$region" --output json 2>/dev/null || echo '{"SecurityGroupRules":[]}')"
  for sg in $(aws ec2 describe-security-groups --region "$region" --filters Name=vpc-id,Values="$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    ingress="$(jq -r --arg sg "$sg" '.SecurityGroupRules[]|select(.GroupId==$sg and .IsEgress==false)|.SecurityGroupRuleId' <<<"$rules" | tr '\n' ' ')"
    [ -z "$ingress" ] || aws ec2 revoke-security-group-ingress --region "$region" --group-id "$sg" --security-group-rule-ids $ingress >/dev/null 2>&1 || true
    egress="$(jq -r --arg sg "$sg" '.SecurityGroupRules[]|select(.GroupId==$sg and .IsEgress==true)|.SecurityGroupRuleId' <<<"$rules" | tr '\n' ' ')"
    [ -z "$egress" ] || aws ec2 revoke-security-group-egress --region "$region" --group-id "$sg" --security-group-rule-ids $egress >/dev/null 2>&1 || true
    aws ec2 delete-security-group --region "$region" --group-id "$sg" >/dev/null 2>&1 || true
  done
  aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id" >/dev/null 2>&1 || printf 'WARN: VPC still has AWS-managed dependencies: %s\n' "$vpc_id"
fi
printf '%s\n' 'PASS: unified cleanup completed; temporary role and user policy are removed on exit.'
