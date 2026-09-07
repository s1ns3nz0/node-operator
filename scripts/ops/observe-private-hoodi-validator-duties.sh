#!/usr/bin/env bash
set -euo pipefail

# Read-only UC-4 assignment observer. It asks the private Beacon API for duty
# assignments only; actual signed outcomes remain correlated later from the
# validator and signer audit streams. It never reads Vault or key material.
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
for command in kubectl curl jq nc mktemp date unlink mkdir chmod; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

mkdir -p "$output_dir"; chmod 700 "$output_dir"; output_dir="$(cd "$output_dir" && pwd -P)"
port="${PRIVATE_BEACON_LOCAL_PORT:-19500}"
nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && { printf 'local beacon port %s is already in use\n' "$port" >&2; exit 75; }
port_log="$(mktemp /private/tmp/node-operator-duty-port.XXXXXX)"; port_pid=''
validator_file="$(mktemp /private/tmp/node-operator-duty-validator.XXXXXX)"
attester_file="$(mktemp /private/tmp/node-operator-duty-attester.XXXXXX)"
proposer_file="$(mktemp /private/tmp/node-operator-duty-proposer.XXXXXX)"
sync_file="$(mktemp /private/tmp/node-operator-duty-sync.XXXXXX)"
cleanup() { set +e; [ -z "$port_pid" ] || kill -TERM "$port_pid" 2>/dev/null || true; [ -z "$port_pid" ] || wait "$port_pid" 2>/dev/null || true; unlink "$port_log" "$validator_file" "$attester_file" "$proposer_file" "$sync_file" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
kubectl -n node-operator port-forward service/prysm-beacon "${port}:3500" >"$port_log" 2>&1 & port_pid=$!
for ((attempt = 1; attempt <= 20; attempt++)); do nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && break; sleep 1; done
nc -z 127.0.0.1 "$port" >/dev/null || { printf 'private beacon port-forward did not become ready\n' >&2; exit 75; }

base_url="http://127.0.0.1:${port}"
sync_json="$(curl --fail --silent --show-error "${base_url}/eth/v1/node/syncing")"
head_slot="$(jq -r '.data.head_slot // empty' <<<"$sync_json")"
case "$head_slot" in ''|*[!0-9]*) printf 'private Beacon response lacks a numeric head slot\n' >&2; exit 65 ;; esac
validator_http="$(curl --silent --show-error --output "$validator_file" --write-out '%{http_code}' "${base_url}/eth/v1/beacon/states/head/validators/${public_key}")"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record="$output_dir/uc-4-private-duties-$(date -u +%Y%m%dT%H%M%SZ).json"

if [ "$validator_http" != 200 ]; then
  jq -n --arg collected "$timestamp" --arg correlation "$correlation_id" --arg set "$validator_set" --arg key "$public_key" --arg status "$validator_http" --argjson syncing "$sync_json" \
    '{schema_version:1,event_type:"uc-4",collected_at_utc:$collected,correlation_id:$correlation,network:"hoodi",validator_set:$set,validator_public_key:$key,source:"private-beacon",payload:{observation_status:"validator-not-active",validator_http_status:$status,syncing:($syncing.data | {head_slot,is_syncing,is_optimistic,el_offline})}}' > "$record"
  printf 'PASS: no duty query made because the validator has no active private Beacon record: %s\n' "$record"
  exit 0
fi

validator_index="$(jq -r '.data.index // empty' "$validator_file")"
case "$validator_index" in ''|*[!0-9]*) printf 'active validator response lacks a numeric index\n' >&2; exit 65 ;; esac
current_epoch=$((head_slot / 32)); next_epoch=$((current_epoch + 1))
attester_http="$(curl --silent --show-error --output "$attester_file" --write-out '%{http_code}' "${base_url}/eth/v1/validator/duties/attester/${current_epoch}?index=${validator_index}")"
proposer_http="$(curl --silent --show-error --output "$proposer_file" --write-out '%{http_code}' "${base_url}/eth/v1/validator/duties/proposer/${current_epoch}")"
sync_http="$(curl --silent --show-error --output "$sync_file" --write-out '%{http_code}' --request POST --header 'Content-Type: application/json' --data "[\"${validator_index}\"]" "${base_url}/eth/v1/validator/duties/sync/${current_epoch}")"
for response_file in "$attester_file" "$proposer_file" "$sync_file"; do
  jq -e 'type == "object"' "$response_file" >/dev/null 2>&1 || printf '{}' > "$response_file"
done

jq -n --arg collected "$timestamp" --arg correlation "$correlation_id" --arg set "$validator_set" --arg key "$public_key" --arg index "$validator_index" --argjson current "$current_epoch" --argjson next "$next_epoch" --arg attester_http "$attester_http" --arg proposer_http "$proposer_http" --arg sync_http "$sync_http" \
  --slurpfile attester "$attester_file" --slurpfile proposer "$proposer_file" --slurpfile sync "$sync_file" '
  {schema_version:1,event_type:"uc-4",collected_at_utc:$collected,correlation_id:$correlation,network:"hoodi",validator_set:$set,validator_public_key:$key,source:"private-beacon",payload:{observation_status:"assignments-observed",validator_index:$index,current_epoch:$current,next_epoch:$next,attester_http_status:$attester_http,proposer_http_status:$proposer_http,sync_http_status:$sync_http,attester_duties:([$attester[0].data[]? | {pubkey,validator_index,committee_index,committee_length,committees_at_slot,validator_committee_index,slot}]),proposer_duties:([$proposer[0].data[]? | select(.validator_index == $index) | {pubkey,validator_index,slot}]),sync_duties:([$sync[0].data[]? | {pubkey,validator_index,validator_sync_committee_indices}])}}' > "$record"
printf 'PASS: private Beacon duty-assignment evidence written to %s\n' "$record"
