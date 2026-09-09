#!/usr/bin/env bash

# Read-only compatibility preflight for recovery wrappers. This library is
# sourced by a caller that owns any later ceremony lifecycle and cancellation.
vault_recovery_auth_preflight() {
  # Never allow xtrace to expose a supplied or tty-entered token.
  set +x

  if ! command -v vault >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'Vault recovery preflight requires vault and jq' >&2
    return 69
  fi

  local status status_rc version major
  if status="$(vault status -format=json 2>/dev/null)"; then
    status_rc=0
  else
    status_rc=$?
  fi
  if [ "$status_rc" -ne 0 ]; then
    printf '%s\n' 'Vault status check failed; recovery preflight cannot continue' >&2
    return 1
  fi
  if ! jq -e '.initialized == true and .sealed == false and (.version | type == "string")' \
      <<<"$status" >/dev/null 2>&1; then
    printf '%s\n' 'Vault must be initialized, unsealed, and return a valid status document' >&2
    return 1
  fi
  version="$(jq -er '.version' <<<"$status" 2>/dev/null)" || {
    printf '%s\n' 'Vault status version is invalid' >&2
    return 1
  }
  if [[ ! "$version" =~ ^([12])\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    printf '%s\n' 'Unsupported or malformed Vault version; recovery preflight fails closed' >&2
    return 1
  fi
  major="${BASH_REMATCH[1]}"

  if [ "$major" = 2 ] && [ -z "${VAULT_TOKEN:-}" ]; then
    # Device permissions alone do not prove a controlling terminal exists.
    # Open the actual device on a private descriptor and suppress its OS error.
    if ! { exec 9<>/dev/tty; } 2>/dev/null; then
      printf '%s\n' 'Vault 2 recovery preflight requires VAULT_TOKEN or an interactive /dev/tty ceremony token' >&2
      return 1
    fi
    printf '%s' 'Vault 2 ceremony token: ' >&9
    if ! IFS= read -r -s VAULT_TOKEN <&9 || [ -z "$VAULT_TOKEN" ]; then
      printf '\n%s\n' 'Vault 2 recovery preflight requires a non-empty ceremony token' >&9
      exec 9>&-
      unset VAULT_TOKEN
      return 1
    fi
    printf '\n' >&9
    exec 9>&-
    export VAULT_TOKEN
  fi

  # This is deliberately the only Vault endpoint called here. It is read-only
  # and validates the supplied v2 ceremony token without starting a ceremony.
  if ! vault operator generate-root -status -format=json >/dev/null 2>&1; then
    printf '%s\n' 'Vault generate-root status authorization check failed' >&2
    return 1
  fi
}
