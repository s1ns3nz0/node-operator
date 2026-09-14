# Hoodi missing-history preparation

This is the narrowly approved Hoodi testnet exception for an existing validator
whose prior signing history cannot be recovered. It does not recover history
and does not guarantee absence of slashing: unknown signatures or another
signer remain risks. It never starts the signer, client, or fence.

The command reads the trusted private Hoodi Beacon and derives a strictly
future slot and epoch floor from the first fresh head. It refuses to proceed if
the final pre-execution head has overtaken that floor. Chain reachability remains pending;
do not activate until the existing guarded activation procedure completes.
Use the intended deployment's private EKS context; keep its declared signer,
client and fence replicas at zero in GitOps throughout maintenance. Stop any
signer for this key outside that cluster separately: Kubernetes cannot verify
an external signer. The current reader is scoped to `hoodi-001` / index 1559065.

Run from a reviewed checkout or a release that contains this command. The
exception ID is your approval/change reference, not an authentication token:

Prerequisites are the deployed Vault database role for `validator-slashing-db`,
its injected CA/password access, and an operator Kubernetes identity that can
read controllers, Pods cluster-wide, PVC/PV, Service/EndpointSlice and Lease,
create Jobs/ConfigMaps/NetworkPolicies, and patch this maintenance Job. The
private Beacon reader verifies Hoodi genesis, sync state, head freshness, and
the public key at index 1559065 through a Pod-bound local port-forward.
No recovery key, keystore password, new key or new deposit is requested.

```sh
scripts/ops/with-private-eks.sh -- scripts/ops/prepare-hoodi-missing-slashing-history.sh \
  --validator-set hoodi-001 --validator-public-key 0x... \
  --exception-approval-id <approved-id> \
  --output-dir /absolute/private/evidence --execute
```

The command independently verifies the stopped signer/client/fence controllers,
absence of their Pods and lease holder, then binds the exact retained database
PVC UID. A temporary maintenance Job uses the staged Web3Signer 26.4.2 native
binary to import an empty public-key record if needed and repair the current
floors. Its only credential source is the existing Vault-backed database password,
injected as a password file and native pool configuration; it mounts no BLS keys
and does not start a signer server. It verifies the
persisted minimum floor for the exact public key and rechecks the stopped paths and PVC
UID before emitting a non-secret receipt. Existing higher watermarks are preserved;
the receipt records the requested minimum, not a claim about recovered history. The fixed suspended Job is a retained
per-validator mutex: it and its owned public-only dependencies remain for
review after success or failure. Review and explicitly remove that retained
mutex before any separately approved rerun; the command never removes it.

An interrupt is not a database rollback. The Job has a 120-second active deadline;
confirm it is terminal and inspect its result before any rerun or activation.
After preparation, use `scripts/ops/activate-hoodi-validator-client.sh` with
its evidence for the existing deposit, fresh private Beacon/signer observations,
and singleton gates. Do not deposit again.
Attestations may be refused until their source epoch reaches the repaired floor.

Success prints `PASS: Hoodi native floor preparation completed` and a private
JSON receipt with `persisted_at_least_requested: true`, `stopped_after: true`,
and `historical_evidence_recovered: false`. The receipt names the retained Job
and UID. A nonzero exit or absent receipt is incomplete, not permission to
activate; inspect the retained Job without publishing raw container logs.
