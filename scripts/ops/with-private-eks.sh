#!/usr/bin/env bash
set -euo pipefail

# Establish a short-lived SSM path to the private EKS API, then run the given
# command with an ephemeral kubeconfig. It neither reads Kubernetes Secrets nor
# prints credential material.
usage() {
  printf 'Usage: %s -- <command> [arguments...]\n' "${0##*/}" >&2
  exit 64
}

[ "${1:-}" = -- ] || usage
shift
[ "$#" -gt 0 ] || usage

for command in aws kubectl nc mktemp unlink; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'missing command: %s\n' "$command" >&2
    exit 69
  }
done

region="${AWS_REGION:-ap-northeast-2}"
cluster_name="${EKS_CLUSTER_NAME:-node-operator}"
instance_id="${SSM_OPS_INSTANCE_ID:-i-02c57d75e7f6810b1}"
eks_port="${PRIVATE_EKS_LOCAL_PORT:-9443}"
session_log="$(mktemp /private/tmp/node-operator-ssm.XXXXXX)"
kubeconfig_file="$(mktemp /private/tmp/node-operator-kubeconfig.XXXXXX)"
session_pid=''

cleanup() {
  set +e
  if [ -n "$session_pid" ]; then
    kill -TERM "$session_pid" 2>/dev/null || true
    wait "$session_pid" 2>/dev/null || true
  fi
  unlink "$session_log" "$kubeconfig_file" 2>/dev/null || true
}
trap cleanup EXIT

endpoint="$(aws eks describe-cluster --name "$cluster_name" --region "$region" --query 'cluster.endpoint' --output text | sed 's#https://##')"
env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY -u GITHUB_TOKEN aws ssm start-session \
  --target "$instance_id" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$endpoint\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$eks_port\"]}" \
  --region "$region" >"$session_log" 2>&1 &
session_pid=$!
for attempt in $(seq 1 30); do
  nc -z 127.0.0.1 "$eks_port" 2>/dev/null && break
  sleep 1
done
nc -z 127.0.0.1 "$eks_port" >/dev/null

aws eks update-kubeconfig --name "$cluster_name" --region "$region" --kubeconfig "$kubeconfig_file" >/dev/null
context="$(kubectl --kubeconfig "$kubeconfig_file" config view --minify -o jsonpath='{.contexts[0].name}')"
kubectl --kubeconfig "$kubeconfig_file" config set-cluster "$context" \
  --server="https://127.0.0.1:${eks_port}" --tls-server-name="$endpoint" >/dev/null

KUBECONFIG="$kubeconfig_file" "$@"
