#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
script="$root/scripts/ops/activate-hoodi-validator-client.sh"
fail() { printf 'FAIL validator activation gate: %s\n' "$*" >&2; exit 1; }
test -f "$script" || fail 'missing activation script'
bash -n "$script"
command -v jq >/dev/null 2>&1 || fail 'jq is required for offline activation-gate tests'

scratch="$(mktemp -d /private/tmp/node-operator-validator-activation.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
public_key="0x$(printf 'a%.0s' {1..96})"
withdrawal_address="0x$(printf 'b%.0s' {1..40})"
validator_set='hoodi-001'
deployment="validator-${validator_set}-client"
now_epoch="$(date -u +%s)"

timestamp() { jq -nr --argjson epoch "$1" '$epoch | strftime("%Y-%m-%dT%H:%M:%S.123Z")'; }

write_valid_evidence() {
  local observed="$1" withdrawal_credentials="0x010000000000000000000000${withdrawal_address#0x}"
  jq -n --arg key "$public_key" --arg withdrawal "$withdrawal_address" '{validator_public_key:$key,withdrawal_address:$withdrawal}' > "$scratch/deposit.json"
  jq -n --arg key "$public_key" --arg set "$validator_set" --arg withdrawal "$withdrawal_credentials" '{network:"hoodi",chain_id:560048,validator_set:$set,validator_public_key:$key,withdrawal_credentials:$withdrawal,deposit_amount_gwei:32000000000,receipt_status:"0x1",ssz_roots_match:true,bls_signature_valid:true,event_matches_public_file:true,secret_material_accessed:false}' > "$scratch/public.json"
  jq -n --arg key "$public_key" --arg set "$validator_set" --arg observed "$observed" '{schema_version:1,event_type:"uc-3",network:"hoodi",validator_set:$set,source:"private-beacon",validator_public_key:$key,collected_at_utc:$observed,payload:{syncing:{is_syncing:false,is_optimistic:false,el_offline:false},validator_http_status:"200",validator:{status:"active_ongoing",validator:{pubkey:$key},index:"123"}}}' > "$scratch/private.json"
  jq -n --arg key "$public_key" --arg set "$validator_set" --arg observed "$observed" '{schema_version:1,event_type:"signer-public-key",network:"hoodi",validator_set:$set,source:"web3signer-tls",validator_public_key:$key,collected_at_utc:$observed,tls_verified:true,public_key_count:1,public_key_match:true}' > "$scratch/signer.json"
  jq -n --arg observed "$observed" '{spec:{holderIdentity:"reviewed-signer-holder",leaseDurationSeconds:300,renewTime:$observed}}' > "$scratch/lease.json"
}

write_valid_inventory() {
  jq -n --arg deployment "$deployment" --arg set "$validator_set" '{items:[{metadata:{namespace:"validator-operations",name:$deployment,labels:{"node-operator.io/validator-set":$set}},spec:{replicas:0,template:{metadata:{labels:{"node-operator.io/validator-set":$set}}}}}]}' > "$scratch/deployments.json"
  printf '%s\n' '{"items":[]}' > "$scratch/pods.json"
  printf '%s\n' '{"items":[]}' > "$scratch/statefulsets.json"
}

cat > "$scratch/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'get deployments --all-namespaces '*) cat "$MOCK_DEPLOYMENTS" ;;
  'get pods --all-namespaces '*) cat "$MOCK_PODS" ;;
  'get statefulsets --all-namespaces '*) cat "$MOCK_STATEFULSETS" ;;
  '-n validator-operations get deployment validator-hoodi-001-remote-signer -o jsonpath={.spec.replicas}') printf '%s' 1 ;;
  '-n validator-operations get lease validator-hoodi-001-primary -o json') cat "$MOCK_LEASE" ;;
  '-n validator-operations scale deployment '*) printf '%s\n' "unexpected scale: $*" >> "$MOCK_TRACE"; exit 70 ;;
  *) printf 'unexpected kubectl invocation: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$scratch/bin/kubectl"

run_gate() {
  PATH="$scratch/bin:$PATH" MOCK_DEPLOYMENTS="$scratch/deployments.json" MOCK_PODS="$scratch/pods.json" MOCK_STATEFULSETS="$scratch/statefulsets.json" MOCK_LEASE="$scratch/lease.json" MOCK_TRACE="$scratch/trace" \
    bash "$script" --validator-set "$validator_set" --deposit-attestation "$scratch/deposit.json" --public-deposit-verification "$scratch/public.json" --private-evidence "$scratch/private.json" --signer-evidence "$scratch/signer.json" --confirm-public-key "$public_key" --confirm-withdrawal-address "$withdrawal_address" --dry-run
}
reset_fixture() { write_valid_evidence "$(timestamp "$now_epoch")"; write_valid_inventory; : > "$scratch/trace"; }
expect_rejected() {
  local name="$1" status
  if run_gate >/dev/null 2>&1; then fail "$name unexpectedly passed"; else status=$?; fi
  test "$status" -eq 65 || fail "$name exited $status instead of 65"
  test ! -s "$scratch/trace" || fail "$name reached a scale request"
}

reset_fixture
run_gate | grep -Fq 'PASS: activation gate passed; no workload was scaled because --dry-run was set.' || fail 'valid fractional-second evidence did not pass dry-run gate'
test ! -s "$scratch/trace" || fail 'happy dry-run reached a scale request'

reset_fixture; write_valid_evidence "$(timestamp $((now_epoch - 301)))"; expect_rejected 'stale private and signer evidence'
reset_fixture; jq --arg observed "$(timestamp $((now_epoch + 61)))" '.collected_at_utc = $observed' "$scratch/private.json" > "$scratch/private.next"; mv "$scratch/private.next" "$scratch/private.json"; expect_rejected 'future private evidence'
reset_fixture; jq 'del(.payload.validator.validator) | .payload.validator.pubkey = .validator_public_key' "$scratch/private.json" > "$scratch/private.next"; mv "$scratch/private.next" "$scratch/private.json"; expect_rejected 'wrong nested validator key'
reset_fixture; jq '.payload.syncing.is_optimistic = true' "$scratch/private.json" > "$scratch/private.next"; mv "$scratch/private.next" "$scratch/private.json"; expect_rejected 'optimistic private evidence'
reset_fixture; jq '.payload.syncing.el_offline = true' "$scratch/private.json" > "$scratch/private.next"; mv "$scratch/private.next" "$scratch/private.json"; expect_rejected 'execution-layer-offline private evidence'
reset_fixture; jq '.event_matches_public_file = false' "$scratch/public.json" > "$scratch/public.next"; mv "$scratch/public.next" "$scratch/public.json"; expect_rejected 'public deposit proof mismatch'
reset_fixture; jq '.validator_set = "hoodi-002"' "$scratch/public.json" > "$scratch/public.next"; mv "$scratch/public.next" "$scratch/public.json"; expect_rejected 'public deposit validator-set mismatch'
reset_fixture; jq '.validator_public_key = ("0x" + ("c" * 96))' "$scratch/signer.json" > "$scratch/signer.next"; mv "$scratch/signer.next" "$scratch/signer.json"; expect_rejected 'signer identity mismatch'
reset_fixture; jq --arg renewed "$(timestamp $((now_epoch - 301)))" '.spec.renewTime = $renewed | .spec.leaseDurationSeconds = 300' "$scratch/lease.json" > "$scratch/lease.next"; mv "$scratch/lease.next" "$scratch/lease.json"; expect_rejected 'expired signer lease'
reset_fixture; jq '.items += [.items[0] | .metadata.name = "validator-hoodi-002-client"]' "$scratch/deployments.json" > "$scratch/deployments.next"; mv "$scratch/deployments.next" "$scratch/deployments.json"; expect_rejected 'multiple cluster-wide client Deployments'
reset_fixture; jq -n '{items:[{metadata:{namespace:"validator-operations",name:"validator-client-pod"}}]}' > "$scratch/pods.json"; expect_rejected 'cluster-wide validator client Pod'
reset_fixture; jq -n '{items:[{metadata:{namespace:"validator-operations",name:"validator-client-statefulset"}}]}' > "$scratch/statefulsets.json"; expect_rejected 'cluster-wide validator client StatefulSet'

printf '%s\n' 'PASS validator activation gate enforces public proof, fresh private/signer evidence, fencing, and exact singleton client inventory offline.'
