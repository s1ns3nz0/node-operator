#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: node-operator-ops-access.sh plan|apply|destroy --root BUNDLE_ROOT --config TFVARS --backend-config BACKEND_HCL [--allow-create]'
}

operation="${1:-}"
[ "$operation" = plan ] || [ "$operation" = apply ] || [ "$operation" = destroy ] || { usage; exit 64; }
shift
root=""; config=""; backend_config=""; allow_create=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    --backend-config) backend_config="${2:-}"; shift 2 ;;
    --allow-create) allow_create=true; shift ;;
    *) usage; exit 64 ;;
  esac
done
[ -d "$root/infra/ops-access" ] || { printf 'ops-access root is missing\n' >&2; exit 1; }
[ -f "$config" ] || { printf 'non-secret tfvars file is required\n' >&2; exit 1; }
[ -f "$backend_config" ] || { printf 'an isolated non-secret backend config is required\n' >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { printf 'terraform is required\n' >&2; exit 127; }

terraform -chdir="$root/infra/ops-access" init -input=false -backend-config="$backend_config"
case "$operation" in
  plan) terraform -chdir="$root/infra/ops-access" plan -input=false -var-file="$config" ;;
  apply)
    [ "$allow_create" = true ] || { printf '%s\n' 'refusing apply: complete reviewed state migration first, then pass --allow-create for a new isolated environment' >&2; exit 1; }
    terraform -chdir="$root/infra/ops-access" apply -input=false -var-file="$config"
    ;;
  destroy)
    [ "$allow_create" = true ] || { printf '%s\n' 'refusing destroy without --allow-create' >&2; exit 1; }
    terraform -chdir="$root/infra/ops-access" destroy -input=false -var-file="$config"
    ;;
esac
