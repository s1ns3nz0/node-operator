"""Read-only private-Beacon verification of one assigned Hoodi attestation."""
import argparse
import json
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--slot", required=True, type=int)
parser.add_argument("--committee", required=True, type=int)
parser.add_argument("--member-index", required=True, type=int)
parser.add_argument("--validator-index", required=True)
parser.add_argument("--public-key", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
if not __debug__ or args.slot < 0 or args.committee < 0 or args.member_index < 0:
    raise SystemExit("invalid verifier execution")

base = "http://127.0.0.1:19500"
def get(path):
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(base + path, timeout=30) as response:
        return json.load(response)
def bits(value): return int.from_bytes(bytes.fromhex(value.removeprefix("0x")), "little")

sync = get("/eth/v1/node/syncing")["data"]
finality = get("/eth/v1/beacon/states/head/finality_checkpoints")
assert not sync["is_syncing"] and not sync["is_optimistic"] and not sync["el_offline"]
assert finality.get("execution_optimistic") is False
identity = get("/eth/v1/beacon/states/head/validators/" + args.validator_index)["data"]
assert identity["validator"]["pubkey"] == args.public_key and not identity["validator"]["slashed"]
committees = get(f"/eth/v1/beacon/states/{args.slot}/committees?slot={args.slot}")
assert committees.get("execution_optimistic") is False
by_index = {int(item["index"]): item["validators"] for item in committees["data"] if int(item["slot"]) == args.slot}
assert args.committee in by_index and by_index[args.committee][args.member_index] == args.validator_index
found = []
for block_slot in range(args.slot + 1, min(int(sync["head_slot"]), args.slot + 32) + 1):
    try: header = get(f"/eth/v1/beacon/headers/{block_slot}")
    except urllib.error.HTTPError as error:
        if error.code == 404: continue
        raise
    assert header["data"]["canonical"] is True and header.get("execution_optimistic") is False
    root = header["data"]["root"]
    block = get("/eth/v2/beacon/blocks/" + root)
    assert block.get("execution_optimistic") is False and block["version"] in ("electra", "fulu")
    for attestation in block["data"]["message"]["body"]["attestations"]:
        if int(attestation["data"]["slot"]) != args.slot: continue
        selected = [i for i in range(64) if bits(attestation["committee_bits"]) & (1 << i)]
        if args.committee not in selected: continue
        aggregate = bits(attestation["aggregation_bits"])
        offset = sum(len(by_index[i]) for i in selected if i < args.committee) + args.member_index
        if aggregate & (1 << offset):
            assert get(f"/eth/v1/beacon/headers/{block_slot}")["data"]["root"] == root
            # A finalized checkpoint for epoch E finalizes every slot in E,
            # whose half-open slot range is [E * 32, (E + 1) * 32).  The
            # previous comparison against E * 32 incorrectly rejected blocks
            # that are inside the finalized epoch itself.
            finalized_epoch = int(finality["data"]["finalized"]["epoch"])
            found.append({"block_slot": block_slot, "block_root": root, "attestation_slot": args.slot, "committee_index": args.committee, "validator_committee_index": args.member_index, "aggregation_bit_index": offset, "canonical": True, "finality_verified": block_slot < (finalized_epoch + 1) * 32, "finalized_checkpoint": finality["data"]["finalized"]})
            break
    if found: break
result = {"schema_version": 1, "event_type": "uc-4-attestation-inclusion", "collected_at_utc": datetime.now(timezone.utc).isoformat(), "network": "hoodi", "validator_index": args.validator_index, "validator_public_key": args.public_key, "source": "private-beacon", "payload": {"verified_inclusion": bool(found), "matches": found, "scope": "Beacon-validated canonical inclusion and assigned committee bit; no independent aggregate BLS verification"}}
Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
