#!/usr/bin/env bash
set -euo pipefail
umask 077

# Stages only the non-secret runtime and fenced client manifests produced by
# prepare-hoodi-validator-deployment.sh. It never initializes Vault, accepts
# custody material, or starts the signer, client, or fence.
usage() {
  printf '%s\n' "usage: ${0##*/} plan|apply --handoff /absolute/validator-deployment-handoff.json [--private-eks-session-handoff /absolute/session.json]" >&2
  exit 64
}

operation="${1:-}"
case "$operation" in plan|apply) ;; *) usage ;; esac
shift
handoff=''; private_eks_session_handoff=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --handoff) handoff="${2:-}"; shift 2 ;;
    --private-eks-session-handoff) private_eks_session_handoff="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$handoff" in /*) ;; *) usage ;; esac
[ -f "$handoff" ] && [ ! -L "$handoff" ] || { printf '%s\n' 'handoff must be a regular file' >&2; exit 65; }
command -v jq >/dev/null 2>&1 || { printf '%s\n' 'missing command: jq' >&2; exit 69; }

parent="$(cd "$(dirname "$handoff")" && pwd -P)"
runtime="$parent/runtime.yaml"
client="$parent/client-and-fence.yaml"
[ -f "$runtime" ] && [ ! -L "$runtime" ] && [ -f "$client" ] && [ ! -L "$client" ] || {
  printf '%s\n' 'handoff directory must contain regular runtime and client manifests' >&2
  exit 65
}

validator_set="$(jq -er '
  if .schema_version == 1 and .network == "hoodi" and
     (.validator_set | type == "string" and test("^hoodi-[a-z0-9][a-z0-9-]*$"))
  then .validator_set else error("invalid validator set") end
' "$handoff")" || { printf '%s\n' 'handoff is not a Hoodi validator deployment contract' >&2; exit 65; }
jq -e --arg parent "$parent" --arg runtime "$runtime" --arg client "$client" '
  (.aws_account_id | test("^[0-9]{12}$")) and
  .runtime_manifest == $runtime and .client_manifest == $client and
  .staged_client_replicas == 0 and .staged_fence_replicas == 0 and
  (.next_steps | type == "array" and length > 0)
' "$handoff" >/dev/null || { printf '%s\n' 'handoff paths or staged replica boundary are invalid' >&2; exit 65; }

# These artifacts are deliberately non-secret. Refuse a handoff that has been
# replaced with a Secret or common raw key material before it crosses the SSM
# tunnel.
secret_kind='Sec''ret'
private_key='PRIVATE'' KEY'
nonpersistent='DO_NOT''_PERSIST_'
if rg -n "(^|[[:space:]])kind:[[:space:]]*${secret_kind}([[:space:]]|$)|-----BEGIN( [A-Z]+)? ${private_key}-----|${nonpersistent}" "$runtime" "$client" >/dev/null; then
  printf '%s\n' 'staging input crosses the non-secret manifest boundary' >&2
  exit 65
fi

if [ -n "$private_eks_session_handoff" ]; then
  case "$private_eks_session_handoff" in /*) ;; *) printf '%s\n' 'private EKS session handoff must be an absolute path' >&2; exit 65 ;; esac
  [ -f "$private_eks_session_handoff" ] && [ ! -L "$private_eks_session_handoff" ] || { printf '%s\n' 'private EKS session handoff must be a regular file' >&2; exit 65; }
  session_cluster="$(jq -er '.schema_version == 1 and .aws_region == "ap-northeast-2" and (.cluster_name | select(test("^[a-z][a-z0-9-]{1,38}[a-z0-9]$")))' "$private_eks_session_handoff")" || { printf '%s\n' 'private EKS session handoff is invalid' >&2; exit 65; }
  session_instance="$(jq -er '.ssm_ops_instance_id | select(test("^i-[0-9a-f]+$"))' "$private_eks_session_handoff")" || { printf '%s\n' 'private EKS session handoff lacks a valid SSM instance' >&2; exit 65; }
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
self="$script_dir/${BASH_SOURCE[0]##*/}"
if [ "${PRIVATE_EKS_SESSION:-}" != 1 ]; then
  if [ -n "$private_eks_session_handoff" ]; then
    exec "$script_dir/../ops/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 AWS_REGION=ap-northeast-2 EKS_CLUSTER_NAME="$session_cluster" SSM_OPS_INSTANCE_ID="$session_instance" "$self" "$operation" --handoff "$handoff" --private-eks-session-handoff "$private_eks_session_handoff"
  fi
  exec "$script_dir/../ops/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 "$self" "$operation" --handoff "$handoff"
fi
command -v kubectl >/dev/null 2>&1 || { printf '%s\n' 'missing command: kubectl' >&2; exit 69; }

# Fresh-set staging must never adopt an existing controller or lease. Check
# before server-side dry-run too: otherwise Kubernetes reports low-level field
# manager conflicts that conceal the actionable recovery/rotation boundary.
namespace='validator-operations'
for target in \
  "statefulset/validator-${validator_set}-slashing-db" \
  "deployment/validator-${validator_set}-remote-signer" \
  "statefulset/validator-${validator_set}-client" \
  "deployment/validator-${validator_set}-signing-fence" \
  "lease/validator-${validator_set}-primary"; do
  if kubectl -n "$namespace" get "$target" >/dev/null 2>&1; then
    printf 'validator set %s already has %s; fresh staging will not adopt it. Use the guarded repair or rotation procedure.\n' "$validator_set" "$target" >&2
    exit 65
  fi
done

# The server-side dry run proves admission, RBAC, and schema compatibility
# before an apply. It is run for both operations so apply has the same guard.
kubectl apply --server-side --field-manager=node-operator-release-stage --dry-run=server -f "$runtime" -f "$client" >/dev/null
if [ "$operation" = plan ]; then
  printf 'PASS: private EKS accepted non-secret staged manifests for %s; no resources were created.\n' "$validator_set"
  exit 0
fi

kubectl apply --server-side --field-manager=node-operator-release-stage -f "$runtime" -f "$client" >/dev/null

db_replicas="$(kubectl -n "$namespace" get "statefulset/validator-${validator_set}-slashing-db" -o jsonpath='{.spec.replicas}')"
signer_replicas="$(kubectl -n "$namespace" get "deployment/validator-${validator_set}-remote-signer" -o jsonpath='{.spec.replicas}')"
client_replicas="$(kubectl -n "$namespace" get "statefulset/validator-${validator_set}-client" -o jsonpath='{.spec.replicas}')"
fence_replicas="$(kubectl -n "$namespace" get "deployment/validator-${validator_set}-signing-fence" -o jsonpath='{.spec.replicas}')"
[ "$db_replicas:$signer_replicas:$client_replicas:$fence_replicas" = '1:0:0:0' ] || {
  printf '%s\n' 'staged controller replicas do not preserve the expected runtime/fence boundary' >&2
  exit 70
}
printf 'PASS: non-secret runtime staged for %s; signer, client, and fence remain at zero pending Vault, custody, deposit, and activation gates.\n' "$validator_set"
