#!/usr/bin/env bash
set -euo pipefail

# Operates only the cost-sensitive Hoodi node pools and the already-reviewed
# client StatefulSets. It never creates, reads, or prints a Secret value.
cluster_name="${EKS_CLUSTER_NAME:-node-operator}"
aws_region="${AWS_REGION:-ap-northeast-2}"
namespace="${HOODI_NAMESPACE:-node-operator}"
consensus_group="${cluster_name}-consensus"
execution_group="${cluster_name}-execution"

usage() {
  printf 'Usage: %s {status|start|stop} [--yes]\n' "${0##*/}" >&2
  exit 64
}

action="${1:-}"
confirmation="${2:-}"
case "$action" in status|start|stop) ;; *) usage ;; esac
if [ "$action" != status ] && [ "$confirmation" != --yes ]; then
  printf '%s requires --yes because it changes runtime capacity.\n' "$action" >&2
  exit 64
fi
if [ "$confirmation" != "" ] && [ "$confirmation" != --yes ]; then usage; fi

require() { command -v "$1" >/dev/null 2>&1 || { printf 'missing required command: %s\n' "$1" >&2; exit 69; }; }
require aws
require kubectl

nodegroup_capacity() {
  aws eks describe-nodegroup --region "$aws_region" --cluster-name "$cluster_name" --nodegroup-name "$1" \
    --query 'nodegroup.scalingConfig.[minSize,desiredSize,maxSize]' --output text
}

wait_nodegroup() {
  aws eks wait nodegroup-active --region "$aws_region" --cluster-name "$cluster_name" --nodegroup-name "$1"
}

require_client_statefulsets() {
  kubectl -n "$namespace" get statefulset nethermind-execution prysm-beacon >/dev/null
}

status() {
  printf 'consensus capacity: '; nodegroup_capacity "$consensus_group"
  printf 'execution capacity: '; nodegroup_capacity "$execution_group"
  kubectl -n "$namespace" get statefulset nethermind-execution prysm-beacon \
    -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas --no-headers
}

start() {
  require_client_statefulsets || {
    printf 'client StatefulSets are absent; promote the reviewed GitOps client revision before starting capacity.\n' >&2
    exit 65
  }
  # This checks only object metadata. Do not inspect .data or decode anything.
  kubectl -n "$namespace" get secret engine-api-jwt -o jsonpath='{.metadata.name}' >/dev/null || {
    printf 'engine-api-jwt object is absent; complete the external Vault custody delivery first.\n' >&2
    exit 65
  }
  aws eks update-nodegroup-config --region "$aws_region" --cluster-name "$cluster_name" \
    --nodegroup-name "$consensus_group" --scaling-config minSize=0,desiredSize=1,maxSize=1 >/dev/null
  aws eks update-nodegroup-config --region "$aws_region" --cluster-name "$cluster_name" \
    --nodegroup-name "$execution_group" --scaling-config minSize=0,desiredSize=1,maxSize=1 >/dev/null
  wait_nodegroup "$consensus_group"
  wait_nodegroup "$execution_group"
  kubectl wait --for=condition=Ready node -l node-operator.io/role=consensus --timeout=20m
  kubectl wait --for=condition=Ready node -l node-operator.io/role=execution --timeout=20m
  kubectl -n "$namespace" scale statefulset nethermind-execution prysm-beacon --replicas=1
  kubectl -n "$namespace" rollout status statefulset/nethermind-execution --timeout=30m
  kubectl -n "$namespace" rollout status statefulset/prysm-beacon --timeout=30m
}

stop() {
  require_client_statefulsets || {
    printf 'client StatefulSets are absent; there is no Hoodi session to stop.\n' >&2
    exit 0
  }
  kubectl -n "$namespace" scale statefulset nethermind-execution prysm-beacon --replicas=0
  kubectl -n "$namespace" wait --for=delete pod -l app.kubernetes.io/part-of=hoodi-node --timeout=20m
  aws eks update-nodegroup-config --region "$aws_region" --cluster-name "$cluster_name" \
    --nodegroup-name "$consensus_group" --scaling-config minSize=0,desiredSize=0,maxSize=1 >/dev/null
  aws eks update-nodegroup-config --region "$aws_region" --cluster-name "$cluster_name" \
    --nodegroup-name "$execution_group" --scaling-config minSize=0,desiredSize=0,maxSize=1 >/dev/null
  wait_nodegroup "$consensus_group"
  wait_nodegroup "$execution_group"
}

"$action"
