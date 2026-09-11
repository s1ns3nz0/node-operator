#!/usr/bin/env bash
# Purpose: Install a fresh, private-ECR, digest-bound cert-manager release.
# The caller provides authenticated private-cluster access and explicit consent.
set -euo pipefail
umask 077
usage() { printf '%s\n' 'usage: deploy-private-cert-manager.sh --chart OCI_DIGEST --values ABSOLUTE_FILE' >&2; exit 64; }
chart='' values=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart=${2:-}; shift 2 ;;
    --values) values=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
[[ $chart =~ ^oci://([0-9]{12})\.dkr\.ecr\.([a-z]{2}(-gov)?-[a-z]+-[0-9])\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$ ]] || usage
account=${BASH_REMATCH[1]}; region=${BASH_REMATCH[2]}
[[ $values = /* ]] && [ -f "$values" ] && [ ! -L "$values" ] || usage
for command in helm kubectl python3; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$script_dir/../../release/cert-manager-values.yaml.example"
[ -f "$template" ] && [ ! -L "$template" ] || { printf 'missing canonical cert-manager values template\n' >&2; exit 69; }
python3 - "$values" "$template" "$account" "$region" <<'PY'
import re
import sys
from pathlib import Path

values_path, template_path, account, region = sys.argv[1:]
values = Path(values_path).read_text(encoding="utf-8")
template = Path(template_path).read_text(encoding="utf-8")
if "REPLACE_WITH_" in values or "__CERT_MANAGER_" in values:
    raise SystemExit("cert-manager values contain unresolved deployment data")
repository_pattern = re.compile(r"^(\s*repository: )([^\s]+)$", re.M)
tag_pattern = re.compile(r"^(\s*tag: )\"?([^\s\"]+)\"?$", re.M)
digest_pattern = re.compile(r"^(\s*digest: )\"?([^\s\"]+)\"?$", re.M)
repositories = repository_pattern.findall(values)
tags = tag_pattern.findall(values)
digests = digest_pattern.findall(values)
private = re.compile(rf"^{re.escape(account)}\.dkr\.ecr\.{re.escape(region)}\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*$")
if len(repositories) != len(tags) or len(repositories) != len(digests) or len(repositories) != 4:
    raise SystemExit("cert-manager values must contain exactly four private repository/tag/digest pairs")
tokens = ("CONTROLLER", "WEBHOOK", "CAINJECTOR", "STARTUPAPICHECK")
expected = template
for token, (_, repository), (_, tag), (_, digest) in zip(tokens, repositories, tags, digests, strict=True):
    if not private.fullmatch(repository) or not re.fullmatch(r"[a-f0-9]{64}", tag) or digest != "sha256:" + tag:
        raise SystemExit("cert-manager values must use matching private-ECR digest-pinned image pairs")
    expected = expected.replace(f"__CERT_MANAGER_{token}_REPOSITORY__", repository)
    expected = expected.replace(f"__CERT_MANAGER_{token}_TAG__", tag)
    expected = expected.replace(f"__CERT_MANAGER_{token}_DIGEST__", tag)
if values != expected:
    raise SystemExit("cert-manager values differ from the fixed hardened template")
PY
for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do
  existing=$(kubectl -n cert-manager get "deployment/$deployment" --ignore-not-found -o name)
  [ -z "$existing" ] || { printf 'cert-manager workload already exists; reconcile it instead of a fresh installation\n' >&2; exit 65; }
done
existing=$(kubectl -n cert-manager get statefulset,daemonset,job --ignore-not-found -o name)
[ -z "$existing" ] || { printf 'cert-manager workload already exists; reconcile it instead of a fresh installation\n' >&2; exit 65; }
if helm status cert-manager --namespace cert-manager >/dev/null 2>&1; then printf 'cert-manager Helm release already exists; reconcile it instead of a fresh installation\n' >&2; exit 65; fi
helm upgrade --install cert-manager "$chart" --namespace cert-manager --create-namespace --values "$values" --set crds.enabled=true --atomic --wait --timeout 15m
for deployment in cert-manager cert-manager-webhook cert-manager-cainjector; do kubectl -n cert-manager rollout status "deployment/$deployment" --timeout=15m; done
for crd in certificates.cert-manager.io issuers.cert-manager.io; do kubectl wait --for=condition=Established "crd/$crd" --timeout=15m; done
printf 'PASS: fresh private cert-manager release is ready; this local helper does not prove live registry or cluster compatibility.\n'
