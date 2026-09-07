#!/usr/bin/env bash
set -euo pipefail

# Read-only UC-3/UC-4 observer. It records selected Beacon API fields only and
# never reads a Vault path, local keystore, validator password, or pod logs.
usage() { printf 'Usage: %s --validator-set <hoodi-id> --validator-public-key <0x-key> --correlation-id <id> --output-dir <absolute-dir>\n' "${0##*/}" >&2; exit 64; }
validator_set=''; public_key=''; correlation_id=''; output_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --validator-public-key) public_key="${2:-}"; shift 2 ;;
    --correlation-id) correlation_id="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
case "$correlation_id" in [a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-]*) ;; *) usage ;; esac
case "$output_dir" in /*) ;; *) usage ;; esac
for command in kubectl curl jq nc mktemp date; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

mkdir -p "$output_dir"; chmod 700 "$output_dir"; output_dir="$(cd "$output_dir" && pwd -P)"
port="${PRIVATE_BEACON_LOCAL_PORT:-19500}"
nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && { printf 'local beacon port %s is already in use\n' "$port" >&2; exit 75; }
port_log="$(mktemp /private/tmp/node-operator-beacon-port.XXXXXX)"; port_pid=''
cleanup() { set +e; [ -z "$port_pid" ] || kill -TERM "$port_pid" 2>/dev/null || true; [ -z "$port_pid" ] || wait "$port_pid" 2>/dev/null || true; unlink "$port_log" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
kubectl -n node-operator port-forward service/prysm-beacon "${port}:3500" >"$port_log" 2>&1 & port_pid=$!
for ((attempt = 1; attempt <= 20; attempt++)); do
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && break
  sleep 1
done
nc -z 127.0.0.1 "$port" >/dev/null || { printf 'private beacon port-forward did not become ready\n' >&2; exit 75; }

sync="$(curl --fail --silent --show-error "http://127.0.0.1:${port}/eth/v1/node/syncing")"
validator_file="$(mktemp /private/tmp/node-operator-validator-state.XXXXXX)"
validator_status="$(curl --silent --show-error --output "$validator_file" --write-out '%{http_code}' "http://127.0.0.1:${port}/eth/v1/beacon/states/head/validators/${public_key}")"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record="$output_dir/uc-3-private-beacon-$(date -u +%Y%m%dT%H%M%SZ).json"
jq -n --arg collected "$timestamp" --arg correlation "$correlation_id" --arg set "$validator_set" --arg key "$public_key" --arg status "$validator_status" --argjson syncing "$sync" --slurpfile validator "$validator_file" '
  {schema_version:1,event_type:"uc-3",collected_at_utc:$collected,correlation_id:$correlation,network:"hoodi",validator_set:$set,validator_public_key:$key,source:"private-beacon",payload:{syncing:($syncing.data | {head_slot,is_syncing,is_optimistic,el_offline}),validator_http_status:$status,validator:($validator[0].data? | if . then {index,status,balance,validator:(.validator | {pubkey,effective_balance,slashed,activation_eligibility_epoch,activation_epoch})} else null end)}}' > "$record"
unlink "$validator_file"
printf 'PASS: private Beacon API evidence written to %s\n' "$record"
