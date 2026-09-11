# Interactive deployment contract

## Commands

The public entrypoint is `scripts/release/node-operator-install.sh`. Its current implementation provides `start`, `status` and `resume` for release consistency checks, read-only AWS discovery and private checkpoints. `ops-access` and provisioning adapters are not implemented yet. `resume` revalidates identity and rejects running stages pending reconciliation; it does not automatically reconcile or retry cloud mutations. `status` reads local state without contacting AWS or Vault. The future `ops-access` command owns a separate Terraform apply and confirmation.

Current local/discovery invocation (not a deployment):

```sh
scripts/release/node-operator-install.sh start \
  --release-dir /absolute/downloaded-release-assets \
  --state-dir /absolute/new-private-checkpoint \
  --aws-profile default --aws-region ap-northeast-1 --name test-node
scripts/release/node-operator-install.sh status --state-dir /absolute/new-private-checkpoint
scripts/release/node-operator-install.sh resume \
  --release-dir /absolute/downloaded-release-assets \
  --state-dir /absolute/new-private-checkpoint
```

Missing initial profile/Region/name values are prompted only in a terminal. Release assets must come from the trusted release workflow; self-consistent manifests are not standalone public-key signature verification. Discovery reports missing local commands by infrastructure, private-access, Vault and optional custody stages; command presence does not prove supported versions or runtime health. It checks account-owned backend bucket names and regional DynamoDB lock-table names without authorizing adoption. Global S3 name availability, provisioning permissions, quotas and remaining resource collisions are still explicitly unverified. Inventory failures stop discovery instead of being treated as empty inventories.

## Input boundaries

| Input | Timing | Source |
| --- | --- | --- |
| Release source and bundle SHA-256 | Before execution | Verified release manifest and downloaded bytes |
| AWS profile, Region, deployment name | First conversation | User; reject malformed values |
| Account and current principal | Preflight | STS using the selected profile, never a hardcoded account |
| AZs, endpoints, resource IDs | Before consuming phase | Read-only discovery or verified Terraform outputs |
| Backend principal | Before bootstrap | Discover a suitable role; if caller is an IAM user, explain and obtain explicit bootstrap authority rather than silently escalating |
| Image sources and destination digests | Before workloads | Release allowlist and verified regional mirror results, not mutable latest tags |
| Validator mode and withdrawal address | Before custody | Explicit new/import choice; validator preparation may be deferred while node infrastructure is built |
| Recovery shares, tokens, keystore password | Exact ceremony | Hidden terminal input; no argv, checkpoint, Git, CI or raw logs |
| Deposit transaction and activation approval | After verified custody | External wallet action; validate network/key/address and wait rather than resubmit |

## Completion states

- `infrastructure_ready`: infrastructure outputs reconciled; not equivalent to a synchronized node.
- `workloads_ready`: private Engine pairing, sync, signer dependencies, policy and log collection verified; validator can remain stopped.
- `awaiting_deposit` / `awaiting_activation`: explicit external dependency, never reported as failed deployment or completed duty.
- `duty_verified`: guarded activation followed by a new canonical finalized duty tied to this key and evidence window.

## Failure handling

Do not automatically delete partially created resources. Record only controlled status codes, keep sensitive tool output outside normal logs, reconcile actual state on resume, and request missing credentials/authority in context. Preserve a running checkpoint after abrupt interruption until its associated resources and operation are inspected. A successful local checkpoint write is not evidence that a remote operation completed.
