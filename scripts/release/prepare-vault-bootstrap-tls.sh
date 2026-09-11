#!/usr/bin/env bash
# Purpose: Prepare only cert-manager-managed Vault listener TLS prerequisites.
# Inputs: --manifest absolute regular YAML file; authenticated private kubectl context.
# Outputs: Certificate readiness and the name-only vault-tls confirmation.
# Side effects: Applies the reviewed manifest and may create only a missing vault namespace.
set -euo pipefail

usage() { printf '%s\n' 'usage: prepare-vault-bootstrap-tls.sh --manifest ABSOLUTE_FILE' >&2; exit 64; }
manifest=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest) [ -z "$manifest" ] || usage; manifest="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$manifest" = /* ]] && [ -f "$manifest" ] && [ ! -L "$manifest" ] || usage
command -v kubectl >/dev/null 2>&1 || { printf '%s\n' 'missing command: kubectl' >&2; exit 69; }

for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do
  kubectl -n cert-manager rollout status "deployment/$deployment" --timeout=10m
done
for crd in certificates.cert-manager.io issuers.cert-manager.io; do
  kubectl wait --for=condition=Established "crd/$crd" --timeout=5m
done
# This is a fresh-TLS prerequisite only; never alter an existing Vault server.
# Assignments deliberately preserve API/RBAC failures under set -e.
namespace="$(kubectl get namespace vault --ignore-not-found -o name)"
if [ -n "$namespace" ]; then
  existing="$(kubectl -n vault get statefulset vault --ignore-not-found -o name)"
  if [ -n "$existing" ]; then
    printf '%s\n' 'Vault StatefulSet already exists; reconcile it rather than applying bootstrap TLS.' >&2
    exit 65
  fi
fi
# Preserve a caller-managed namespace exactly; a fresh deployment may create
# only this namespace, with the repository's restricted Pod Security labels.
if [ -z "$namespace" ]; then
  kubectl create namespace vault
  kubectl label namespace vault \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/audit-version=latest \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/warn-version=latest
fi
kubectl apply -f "$manifest"
for certificate in vault-internal-ca vault-server-tls; do
  kubectl -n vault wait --for=condition=Ready "certificate/$certificate" --timeout=10m
done
kubectl -n vault get secret vault-tls -o name | grep -qx 'secret/vault-tls'
printf '%s\n' 'PASS: cert-manager created Vault TLS prerequisites; no Vault installation or initialization was performed.'
