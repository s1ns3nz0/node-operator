#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  node-operator-release.sh verify --bundle-root DIRECTORY
  node-operator-release.sh bootstrap plan|apply --bundle-root DIRECTORY --config FILE

`verify` validates every archived source/rendered file against bundle-manifest.json.
`bootstrap` runs only the non-secret Terraform baseline. It never creates an
SSM host, initializes Vault, reads a Secret, or enables a validator signer.
USAGE
}

fail() { printf 'release bootstrap: %s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"; }

command_name="${1:-}"
[ -n "$command_name" ] || { usage; exit 64; }
shift

bundle_root=""
config=""
operation=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle-root) bundle_root="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    plan|apply) operation="$1"; shift ;;
    *) usage; fail "unsupported argument: $1" ;;
  esac
done

[ -n "$bundle_root" ] || fail "--bundle-root is required"
[ -d "$bundle_root/source" ] || fail "bundle root must contain source/"
[ -f "$bundle_root/bundle-manifest.json" ] || fail "bundle root must contain bundle-manifest.json"
require_command jq
require_command shasum

verify_bundle() {
  local bad=0 path expected actual
  while IFS=$'\t' read -r path expected; do
    [ -f "$bundle_root/$path" ] || { printf 'missing archived path: %s\n' "$path" >&2; bad=1; continue; }
    actual="$(shasum -a 256 "$bundle_root/$path" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || { printf 'digest mismatch: %s\n' "$path" >&2; bad=1; }
  done < <(jq -r '.entries[] | [.path, .sha256] | @tsv' "$bundle_root/bundle-manifest.json")
  [ "$bad" -eq 0 ] || fail "bundle verification failed"
  jq -e '
    .schema_version == "v1" and
    .network == "hoodi" and
    .client_chart.revision == "0.1.28" and
    (.bootstrap.forbidden_inputs | length > 0)
  ' "$bundle_root/source/release/hoodi-release-contract.json" >/dev/null || fail "release contract is invalid"
  printf 'PASS release bundle and Hoodi contract verified.\n'
}

case "$command_name" in
  verify)
    [ -z "$operation$config" ] || fail "verify accepts only --bundle-root"
    verify_bundle
    ;;
  bootstrap)
    [ "$operation" = plan ] || [ "$operation" = apply ] || fail "bootstrap requires plan or apply"
    [ -n "$config" ] && [ -f "$config" ] || fail "--config must name a readable non-secret tfvars file"
    verify_bundle
    if rg -n '^[[:space:]]*enable_temporary_ssm_ops_host[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$config" >/dev/null; then
      fail "SSM operations access belongs to the isolated ops-access command"
    fi
    if rg -n '^[[:space:]]*enable_(argocd|vault)_bootstrap_cluster_admin[[:space:]]*=[[:space:]]*true([[:space:]]|$)' "$config" >/dev/null; then
      fail "temporary cluster-admin bootstrap requires its separately approved phase"
    fi
    require_command terraform
    terraform -chdir="$bundle_root/source/infra/terraform" init -input=false
    if [ "$operation" = plan ]; then
      terraform -chdir="$bundle_root/source/infra/terraform" plan -input=false -var-file="$config"
    else
      terraform -chdir="$bundle_root/source/infra/terraform" apply -input=false -var-file="$config"
    fi
    ;;
  *) usage; fail "unsupported command: $command_name" ;;
esac
