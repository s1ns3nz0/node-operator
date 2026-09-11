# Hoodi UC-5 revalidation

Scope: the existing `hoodi-001` validator, signer runtime role, retained slashing
database and private Seoul cluster. This is not a new deployment or key ceremony.
Run the reviewed, merged revision only. Never use the legacy broad-bootstrap
revocation wrapper for this procedure.

Audit readiness requires the deployed relay's version-1 provenance envelopes.
The relay preserves file and socket records but labels their input source; UC-5
uses only `audit_source: socket`, matching the `validator-socket` HMAC device.
Legacy unlabeled records cannot prove readiness or denial. Update the pinned
relay image and verify ingestion before requesting another recovery ceremony.
Do not relax conflicting-record checks to combine devices with different salts.

## 1. User-only recovery and role exercise

Choose a new absolute directory whose parent exists:

```bash
ceremony_dir="$HOME/node-operator-evidence/uc5-$(date -u +%Y%m%dT%H%M%SZ)"
scripts/ops/recover-and-run-hoodi-uc5.sh --evidence-dir "$ceremony_dir"
```

The wrapper establishes private access and runs non-destructive admission and
Beacon checks before asking for `UC5` confirmation and recovery shares on the
local terminal. Do not put shares or tokens in commands, chat or evidence.
After root/audit readiness checks it fences the client, exercises only the
signer role, restores the exact role, verifies continuity and revokes root.

`PROBE_COMPLETE` is **not UC-5 completion**. Client and Fence deliberately remain
at zero. A failed or cleanup-unconfirmed outcome must not be activated.

## 2. Fresh post-recovery evidence, without root

Use a different, empty private directory. The original evidence remains intact.

```bash
activation_dir="${ceremony_dir}-activation"
mkdir -m 700 "$activation_dir"
scripts/ops/with-private-vault.sh -- env PRIVATE_VAULT_SESSION=1 \
  python3 scripts/ops/run-hoodi-uc5-ceremony.py prepare-activation \
  --ceremony-dir "$ceremony_dir" --evidence-dir "$activation_dir"
```

This checks successful role restoration/root revocation evidence, then recollects
same-instance signer, retained-PVC/history, mTLS and private Beacon proof. It
does not scale anything. Its output uses the existing activation gate's schemas.

## 3. Existing single activation gate

Immediately use the fresh files with the already reviewed public deposit proofs:

```bash
scripts/ops/with-private-eks.sh -- scripts/ops/activate-hoodi-validator-client.sh \
  --validator-set hoodi-001 \
  --deposit-attestation "$HOME/node-operator-evidence/uc14-20260910/uc-1/public-deposit/uc-1-deposit-attestation.json" \
  --public-deposit-verification "$HOME/node-operator-evidence/uc14-20260910/uc-1/activation-public-proof-20260911.json" \
  --private-evidence "$activation_dir/private-activation-evidence.json" \
  --signer-evidence "$activation_dir/signer-activation-evidence.json" \
  --confirm-public-key 0xa3866b82651039224bfd725fc81e7ff17c1765021dff37f3fd4bc01405e2ed14c97c7c5c82cd95104d8f82c4229ab0d0 \
  --confirm-withdrawal-address 0x403ff64383b8ddf994d5563550c8040d89f025ac
```

The activation gate refuses existing maintenance markers and changed controller
UIDs. Evidence expires after five minutes; recollect it if stale. Do not bypass
the gate or start a second validator client.

## 4. Completion evidence and failure handling

Collect three new post-activation duties, at least one privately/publicly
corroborated canonical finalized inclusion, and matching signer audit/slashing-DB
evidence. Preserve the role delete/denied-login/restore audit chain separately.
Neither Pod readiness nor activation success satisfies this completion condition.

If `uc5-hoodi-001-maintenance` remains, stop activation attempts. Read its UID and
`node-operator.io/ceremony-id`, inspect only metadata for owned diagnostic Pods,
and reconcile the recorded failure. Do not blindly delete the marker: verify
diagnostic cleanup, client/Fence quiescence, exact role restoration and credential
cleanup first, then remove only the verified owned marker with UID/resourceVersion
preconditions. A different owner or uncertain cleanup requires operator review.
