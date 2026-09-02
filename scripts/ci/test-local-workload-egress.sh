#!/usr/bin/env bash
set -euo pipefail

context="kind-node-operator-cilium"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! kubectl config get-contexts -o name | grep -Fxq "$context"; then
  echo "Required local-only context $context is unavailable." >&2
  exit 1
fi

cleanup() {
  kubectl --context "$context" delete namespace node-operator node-operator-gateway --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "$context" apply -f "$root/deploy/base/namespace.yaml"
kubectl --context "$context" apply -f "$root/deploy/base/network-policies.yaml"
kubectl --context "$context" apply -f "$root/deploy/prysm/network-policies.yaml"
kubectl --context "$context" apply -f "$root/deploy/nethermind/network-policies.yaml"
kubectl --context "$context" apply -f "$root/deploy/local-egress/fixtures.yaml"

kubectl --context "$context" -n node-operator-gateway wait --for=condition=Ready pod/hoodi-p2p-gateway pod/hoodi-https-gateway --timeout=120s
kubectl --context "$context" -n node-operator wait --for=condition=Ready pod/prysm-egress-probe pod/nethermind-egress-probe --timeout=120s

p2p_ip="$(kubectl --context "$context" -n node-operator-gateway get pod hoodi-p2p-gateway -o jsonpath='{.status.podIP}')"
https_ip="$(kubectl --context "$context" -n node-operator-gateway get pod hoodi-https-gateway -o jsonpath='{.status.podIP}')"

allow_tcp() { kubectl --context "$context" -n node-operator exec "$1" -- nc -z -w 3 "$2" "$3"; }
allow_udp_echo() { printf '%s' "$4" | kubectl --context "$context" -n node-operator exec -i "$1" -- nc -u -w 3 "$2" "$3" | grep -Fxq "$4"; }
deny_tcp() {
  if kubectl --context "$context" -n node-operator exec "$1" -- nc -z -w 3 "$2" "$3" >/dev/null 2>&1; then
    echo "Unexpected allowed path: $1 -> $2:$3" >&2
    exit 1
  fi
}

kubectl --context "$context" -n node-operator exec prysm-egress-probe -- nslookup kubernetes.default.svc.cluster.local >/dev/null
allow_tcp prysm-egress-probe "$p2p_ip" 13000
allow_udp_echo prysm-egress-probe "$p2p_ip" 13000 prysm-udp
allow_tcp prysm-egress-probe "$https_ip" 443
deny_tcp prysm-egress-probe "$p2p_ip" 30303
deny_tcp prysm-egress-probe 1.1.1.1 443

kubectl --context "$context" -n node-operator exec nethermind-egress-probe -- nslookup kubernetes.default.svc.cluster.local >/dev/null
allow_tcp nethermind-egress-probe "$p2p_ip" 30303
allow_udp_echo nethermind-egress-probe "$p2p_ip" 30303 nethermind-udp
allow_tcp nethermind-egress-probe "$https_ip" 443
deny_tcp nethermind-egress-probe "$p2p_ip" 13000
deny_tcp nethermind-egress-probe 1.1.1.1 443

echo "PASS Cilium enforced Prysm and Nethermind controlled-egress allowlists."
