#!/usr/bin/env bash
set -euo pipefail

# Public corroboration only. Private Beacon results remain operational truth.
# ETHERSCAN_API_KEY and BEACONCHAIN_API_TOKEN are read only from the
# environment. Neither is emitted, retained in evidence, or placed in a URL.
usage() { printf 'Usage: %s --validator-set <hoodi-id> --validator-public-key <0x-key> --correlation-id <id> --output-dir <absolute-dir> [--deposit-tx <0x-hash>]\n' "${0##*/}" >&2; exit 64; }
validator_set=''; public_key=''; correlation_id=''; output_dir=''; deposit_tx=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validator-set) validator_set="${2:-}"; shift 2 ;;
    --validator-public-key) public_key="${2:-}"; shift 2 ;;
    --correlation-id) correlation_id="${2:-}"; shift 2 ;;
    --output-dir) output_dir="${2:-}"; shift 2 ;;
    --deposit-tx) deposit_tx="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
case "$validator_set" in hoodi-[a-z0-9][a-z0-9-]*) ;; *) usage ;; esac
case "$public_key" in 0x????????????????????????????????????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
case "$correlation_id" in [a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-][a-f0-9-]*) ;; *) usage ;; esac
case "$output_dir" in /*) ;; *) usage ;; esac
case "$deposit_tx" in ''|0x????????????????????????????????????????????????????????????????) ;; *) usage ;; esac
for command in curl jq shasum mkdir date mktemp unlink chmod; do command -v "$command" >/dev/null 2>&1 || { printf 'missing command: %s\n' "$command" >&2; exit 69; }; done

mkdir -p "$output_dir"; chmod 700 "$output_dir"; output_dir="$(cd "$output_dir" && pwd -P)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
deposit_contract='0x00000000219ab540356cbb839cbe05303d7705fa'
record_base="$output_dir/external-$(date -u +%Y%m%dT%H%M%SZ)"

beacon_tmp="$(mktemp /private/tmp/node-operator-beaconcha.XXXXXX)"
beacon_config="$(mktemp /private/tmp/node-operator-beaconcha-curl.XXXXXX)"
etherscan_config=''
trap 'unlink "$beacon_tmp" "$beacon_config" "${etherscan_tmp:-}" "$etherscan_config" 2>/dev/null || true' EXIT
beacon_url='https://beaconcha.in/api/v2/ethereum/validators'
beacon_result='not-configured'
if [ -n "${BEACONCHAIN_API_TOKEN:-}" ]; then
  chmod 600 "$beacon_config"
  printf '%s\n' 'header = "Content-Type: application/json"' "header = \"Authorization: Bearer ${BEACONCHAIN_API_TOKEN}\"" > "$beacon_config"
  beacon_request="$(jq -cn --arg key "$public_key" '{chain:"hoodi",validator:{validator_identifiers:[$key]},page_size:1}')"
  if curl --fail --silent --show-error --max-time 20 --config "$beacon_config" --request POST --header 'Accept: application/json' --data "$beacon_request" --output "$beacon_tmp" "$beacon_url"; then beacon_result='observed'; else beacon_result='unavailable'; printf '{}' > "$beacon_tmp"; fi
else
  printf '{}' > "$beacon_tmp"
fi
beacon_sha="$(shasum -a 256 "$beacon_tmp" | awk '{print $1}')"
jq -n --arg collected "$timestamp" --arg correlation "$correlation_id" --arg set "$validator_set" --arg key "$public_key" --arg url "$beacon_url" --arg result "$beacon_result" --arg sha "$beacon_sha" \
  '{schema_version:1,event_type:"uc-3",collected_at_utc:$collected,correlation_id:$correlation,network:"hoodi",validator_set:$set,validator_public_key:$key,source:"beaconcha-in",payload:{verification_status:$result,explorer_url:$url,api_version:"v2",response_sha256:$sha}}' > "${record_base}-beaconcha-in.json"

if [ -n "$deposit_tx" ]; then
  : "${ETHERSCAN_API_KEY:?Set ETHERSCAN_API_KEY in the environment; do not put it in command history.}"
  etherscan_tmp="$(mktemp /private/tmp/node-operator-etherscan.XXXXXX)"
  etherscan_config="$(mktemp /private/tmp/node-operator-etherscan-curl.XXXXXX)"
  chmod 600 "$etherscan_config"
  printf '%s\n' "url = \"https://api.etherscan.io/v2/api?chainid=560048&module=proxy&action=eth_getTransactionReceipt&txhash=${deposit_tx}&apikey=${ETHERSCAN_API_KEY}\"" > "$etherscan_config"
  curl --fail --silent --show-error --max-time 20 --config "$etherscan_config" --output "$etherscan_tmp"
  receipt_sha="$(shasum -a 256 "$etherscan_tmp" | awk '{print $1}')"
  receipt_status="$(jq -r '.result.status // "unknown"' "$etherscan_tmp")"
  event_observed="$(jq -r --arg contract "$deposit_contract" '[.result.logs[]?.address | ascii_downcase == $contract] | any' "$etherscan_tmp")"
  jq -n --arg collected "$timestamp" --arg correlation "$correlation_id" --arg set "$validator_set" --arg key "$public_key" --arg tx "$deposit_tx" --arg status "$receipt_status" --arg sha "$receipt_sha" --argjson event "$event_observed" \
    '{schema_version:1,event_type:"uc-1",collected_at_utc:$collected,correlation_id:$correlation,network:"hoodi",validator_set:$set,validator_public_key:$key,source:"etherscan",payload:{verification_status:(if $status == "0x1" and $event then "observed" else "not-confirmed" end),explorer_url:("https://hoodi.etherscan.io/tx/" + $tx),transaction_hash:$tx,receipt_status:$status,deposit_contract_event_observed:$event,response_sha256:$sha}}' > "${record_base}-etherscan.json"
fi
printf 'PASS: external corroboration evidence written with no explorer response body retained.\n'
