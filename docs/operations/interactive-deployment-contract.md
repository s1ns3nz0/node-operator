# Interactive deployment contract

## Commands

The public entrypoint is `scripts/release/node-operator-install.sh`. Its current implementation provides `start`, `status` and `resume` for release consistency checks, read-only AWS discovery and private checkpoints. `start` and `resume` additionally accept `--prepare-infrastructure` to materialize the trusted release and generate private Terraform input files, without applying infrastructure. `ops-access` and cloud provisioning adapters are not implemented yet. `resume` revalidates identity and rejects running stages pending reconciliation; it does not automatically reconcile or retry cloud mutations. `status` reads local state without contacting AWS or Vault. The future `ops-access` command owns a separate Terraform apply and confirmation.

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

Missing initial profile/Region/name values are prompted only in a terminal. Release assets must come from the trusted release workflow; self-consistent manifests are not standalone public-key signature verification. Discovery reports missing local commands by infrastructure, private-access, Vault and optional custody stages; command presence does not prove supported versions or runtime health. It checks account-owned backend bucket names, regional DynamoDB lock-table names, and account-wide IAM role names under the deployment's foundation/baseline namespaces without authorizing adoption. Global S3 name availability, IAM policy attachments, provisioning permissions, quotas and remaining resource collisions are still explicitly unverified. Inventory failures stop discovery instead of being treated as empty inventories.

## Local infrastructure preparation

Add `--prepare-infrastructure` to `start` or `resume`. Supply
`--backend-principal-arn arn:aws:iam::<account>:role/<backend-role>` or answer
the role prompt. This creates `release/` and `infrastructure-inputs/` under the
private state directory. Existing release bytes, file permissions and input
values must still match on reuse; changed files are not overwritten. The role
is checked for same-account ARN syntax and then queried with `iam:GetRole` using
the selected profile. Its exact ARN and unique role ID must be returned before
release materialization or input generation. This verifies existence, not role
trust, assume-role access or effective backend/provisioning permissions. A missing
role or denied lookup stops preparation with an actionable message. No role or
IAM policy is created, and Terraform is not run.
When the inventory profile and deployment role profile differ, add
`--execution-profile <existing-profile>`. The installer uses STS under that
profile and compares its account, assumed-role ARN and unique role ID with
the IAM identity returned by the inventory profile. The execution profile
does not need `iam:GetRole`; the inventory profile still does. The CLI may
use its normal profile credential cache, but the installer never receives or
stores access-key/session-token values. This option verifies identity only:
no IAM policies are attached, no Terraform command runs, and no permission
success is claimed. The execution profile is not persisted as an apply
authorization; it must be supplied and reverified on a later execution path.
`infrastructure_inputs_ready` is a preparation result, not a deployment result.
Newly generated baseline inputs also set `terraform_apply_role_arn` to the
selected role, eliminating the mandatory historical role name from new KMS
lifecycle policies. Both primary and replica policies use it; cross-account
roles fail Terraform preconditions. Omitted overrides preserve the historical
role on existing deployments. This does not assume the role, attach its IAM
permissions or prove that Terraform executes as that role. Old prepared inputs
and old release bundles lack this field and need a new verified release/input
set; the installer never silently edits them in place.
Publishing the release and inputs uses the OS no-replace rename operation
(macOS or Linux with supported libc/filesystem). Unsupported platforms fail
without falling back to an operation that could replace an existing directory.

## Capacity observation

Discovery compares the regional EC2 Elastic IP quota (`L-0263D0A3`) with
allocated addresses and the fresh foundation's one required NAT address.
It reports a lower bound on remaining capacity, not a reservation or complete
quota clearance. All allocations are conservatively counted: AWS excludes
some customer-owned pools from the limit ([AWS Elastic IP documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)).
A shortfall requires capacity review, never automatic address deletion.
vCPU, NAT gateway, VPC, endpoint and other quotas remain unverified.

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

The release infrastructure wrapper now rejects enabled SSM/temporary
cluster-admin flags and caller-supplied derived network fields in JSON as well
as HCL inputs. The generic credential-field screen now inspects nested JSON
keys, and `zero apply --inputs` compares the generated manifest's account,
Region, name and AZs with the three phase files before Terraform executes.
This proves input consistency, not AWS identity, full secret detection or
effective permissions. Individually supplied HCL configs do not have this
manifest binding. Do not connect automatic apply until caller authorization
and state-aware partial-apply recovery are implemented. In particular,
an existing bootstrap/foundation module without an output checkpoint is now
reconciled in place: original backend/state, a zero-change plan and a successful
output query are required to reconstruct the checkpoint. Baseline recovery uses
the same path, additionally checking its original derived network input and exact
S3 backend. A completed baseline is reconciled without recopying module sources
or applying resources again. No resource apply is repeated on these recovery
paths. A remaining change plan still stops for review; approved execution of
residual changes remains unfinished.

Do not automatically delete partially created resources. Record only controlled status codes, keep sensitive tool output outside normal logs, reconcile actual state on resume, and request missing credentials/authority in context. Preserve a running checkpoint after abrupt interruption until its associated resources and operation are inspected. A successful local checkpoint write is not evidence that a remote operation completed.
