#!/usr/bin/env bash
set -euo pipefail

# Extends with-private-eks.sh with a CA-validated, short-lived Vault port
# forward. The Vault CA is public; no token, private key, or Secret data is
# read or printed by this wrapper.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
usage() {
  printf 'Usage: %s [--bootstrap] -- <command> [arguments...]\n' "${0##*/}" >&2
  exit 64
}
bootstrap=0
if [ "${1:-}" = --bootstrap ]; then bootstrap=1; shift; fi
[ "${1:-}" = -- ] || usage
shift
[ "$#" -gt 0 ] || usage

exec "$root/scripts/ops/with-private-eks.sh" -- env PRIVATE_EKS_SESSION=1 VAULT_BOOTSTRAP="$bootstrap" \
  bash -c '
    set -euo pipefail
    for command in kubectl nc mktemp unlink openssl; do
      command -v "$command" >/dev/null 2>&1 || { printf "missing command: %s\\n" "$command" >&2; exit 69; }
    done
    vault_port="${PRIVATE_VAULT_LOCAL_PORT:-18200}"
    temp_base="${TMPDIR:-/tmp}"
    port_log="$(mktemp "$temp_base/node-operator-vault-port.XXXXXX")"
    ca_file="$(mktemp "$temp_base/node-operator-vault-ca.XXXXXX")"
    port_pid=""
    cleanup() {
      cleanup_status=0
      set +e
      if [ -n "$port_pid" ]; then kill -TERM "$port_pid" 2>/dev/null || true; wait "$port_pid" 2>/dev/null || true; fi
      unlink "$port_log" || cleanup_status=1
      unlink "$ca_file" || cleanup_status=1
      return "$cleanup_status"
    }
    signal_cleanup() { cleanup; exit 128; }
    trap signal_cleanup TERM HUP INT
    trap "status=\$?; cleanup || { [ \$status -eq 0 ] && status=70; }; exit \$status" EXIT
    kubectl -n vault exec vault-0 -- sh -c "dd if=/vault/userconfig/vault-tls/ca.crt 2>/dev/null" > "$ca_file"
    chmod 600 "$ca_file"
    openssl x509 -in "$ca_file" -noout >/dev/null 2>&1 || { printf "Vault CA is not a valid PEM certificate\\n" >&2; exit 65; }
    target="service/vault-active"
    [ "${VAULT_BOOTSTRAP:-0}" = 1 ] && target="pod/vault-0"
    kubectl -n vault port-forward "$target" "${vault_port}:8200" >"$port_log" 2>&1 &
    port_pid=$!
    for attempt in $(seq 1 20); do nc -z 127.0.0.1 "$vault_port" 2>/dev/null && break; sleep 1; done
    nc -z 127.0.0.1 "$vault_port" >/dev/null
    VAULT_ADDR="https://127.0.0.1:${vault_port}" VAULT_CACERT="$ca_file" VAULT_TLS_SERVER_NAME="vault.vault.svc" "$@"
  ' -- "$@"
