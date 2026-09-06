#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: node-operator-ops-access.sh plan|apply|destroy --root BUNDLE_ROOT --config TFVARS'
}

operation="${1:-}"
[ "$operation" = plan ] || [ "$operation" = apply ] || [ "$operation" = destroy ] || { usage; exit 64; }
shift
root=""; config=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    *) usage; exit 64 ;;
  esac
done
[ -d "$root/infra/ops-access" ] || { printf 'ops-access root is missing\n' >&2; exit 1; }
[ -f "$config" ] || { printf 'non-secret tfvars file is required\n' >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { printf 'terraform is required\n' >&2; exit 127; }

terraform -chdir="$root/infra/ops-access" init -input=false
case "$operation" in
  plan) terraform -chdir="$root/infra/ops-access" plan -input=false -var-file="$config" ;;
  apply) terraform -chdir="$root/infra/ops-access" apply -input=false -var-file="$config" ;;
  destroy) terraform -chdir="$root/infra/ops-access" destroy -input=false -var-file="$config" ;;
esac
