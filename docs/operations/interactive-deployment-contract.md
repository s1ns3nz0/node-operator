# Interactive deployment contract

## Commands

The planned public interface provides `start`, `status`, `resume`, and `ops-access` commands. These are design contracts, not a claim that all commands exist yet. `start` collects minimal input and preflights; `resume` revalidates identity and reconciles the interrupted phase; `status` reads local state without contacting Vault; `ops-access` owns a separate Terraform apply and confirmation.

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
