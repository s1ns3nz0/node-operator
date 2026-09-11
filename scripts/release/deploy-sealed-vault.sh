#!/usr/bin/env bash
# Purpose: Install a fresh, digest-bound Vault release without initializing it.
# Inputs: Private OCI chart digest and reviewed non-secret values file.
# Outputs: Sealed/uninitialized verification only; never root or recovery material.
# Side effects: Installs the approved Helm release; requires separately granted access.
set -euo pipefail
umask 077
chart=''; values=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart="${2:-}"; shift 2 ;;
    --values) values="${2:-}"; shift 2 ;;
    *) printf 'Usage: deploy-sealed-vault.sh --chart OCI_DIGEST --values ABSOLUTE_FILE\n' >&2; exit 64 ;;
  esac
done
[[ "$chart" =~ ^oci://[0-9]{12}\.dkr\.ecr\.ap-northeast-(1|2)\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$ ]] || exit 64
[[ "$values" = /* ]] && [ -f "$values" ] && [ ! -L "$values" ] || exit 64
for command in helm kubectl jq mktemp; do
  command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }
done
if grep -q 'REPLACE_WITH_' "$values"; then
  printf 'Vault values contain unresolved deployment inputs\n' >&2; exit 65
fi
# A fresh-install helper must never upgrade or reinitialize an existing server.
existing="$(kubectl -n vault get statefulset vault --ignore-not-found -o name)"
[ -z "$existing" ] || { printf 'Vault already exists; reconcile it instead of running fresh installation\n' >&2; exit 65; }
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sealed-vault-check.XXXXXX")"
trap 'rm -f "$scratch/status.json"; rmdir "$scratch"' EXIT
# --atomic implies --wait and would roll back sealed, uninitialized Vault.
# Verify its expected bootstrap state explicitly instead; retain failures for recovery.
helm upgrade --install vault "$chart" --namespace vault --values "$values" --timeout 15m
for pod in vault-0 vault-1 vault-2; do
  # Helm returns before the StatefulSet controller necessarily creates every Pod.
  kubectl -n vault wait --for=create "pod/$pod" --timeout=15m
  kubectl -n vault wait --for=jsonpath='{.status.phase}'=Running "pod/$pod" --timeout=15m
  status=0
  kubectl -n vault exec "$pod" -c vault -- env \
    "VAULT_ADDR=https://${pod}.vault-internal:8200" \
    "VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt" \
    vault status -format=json > "$scratch/status.json" || status=$?
  [ "$status" -eq 2 ] || { printf 'Unexpected Vault bootstrap status for %s; initialization was not attempted\n' "$pod" >&2; exit 65; }
  jq -e '.initialized == false and .sealed == true and .storage_type == "raft"' "$scratch/status.json" >/dev/null || {
    printf 'Vault is not sealed and uninitialized with Raft storage: %s\n' "$pod" >&2; exit 65;
  }
done
printf 'PASS: three Vault Pods are running, sealed and uninitialized; revoke bootstrap authority before the separate initialization ceremony.\n'
