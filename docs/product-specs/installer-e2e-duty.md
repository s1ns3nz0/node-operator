# Single-entry installer through verified validator duties

Status: approved. Authority: [E2E scope decision](../decisions/2026-09-13-installer-e2e-duty-scope.md).

## Scope and start condition

Deliver a single interactive installation entrypoint, using v0.1.20 as the baseline and shipping changes in a new immutable release. Do not move the existing tag. Run E2E from the downloaded release in a clean directory, not from a development checkout. Default to Seoul (`ap-northeast-2`) and test this one Region.

The test starts with no node-operator deployment resources in the target scope. Preserve unrelated projects, validator custody and slashing protection records. Inventory and exact ownership checks must distinguish an existing backend belonging to this deployment from unrelated Terraform infrastructure. Protected retained resources must be reported; their existence must not be described as a fully empty start, nor bypassed by deleting protected data. Resolving such an exception requires a separate explicit decision.

UC-1 through UC-5 exercises, fault-injection campaigns, UC reports and waiting for a block proposal are excluded. Normal deployment safety checks and operational logging remain required.

### Existing-account and empty-account coverage

The user additionally requires testing deployment into an empty AWS account. Keep this distinct from a new deployment scope inside an existing account. Retained custody, slashing history and audit backups are preserved with user approval; their presence must remain visible in start-condition evidence.

Both currently configured profiles (`default`, `node-operator-t2`) resolve to account `106760547719`, and the user confirmed no separate account is available. Do not create another account implicitly. Continue existing-account work and exercise absent-state/ECR/OIDC/IAM creation paths in automated tests. Actual empty-account deployment remains explicitly unverified until a separate account and execution authorization are available. Neither mocks nor deleting this project's resources qualify as that acceptance result. No second deployment may concurrently activate the existing signing key.

## Execution inputs

T01 must map the approved release's existing clients, schemas, topology, ownership tags and logging destinations to this lifecycle rather than invent alternatives. Resolve the AWS account through caller identity and user confirmation; bind deployment identity and repositories through the validated inputs and Terraform outputs. Choose the new version from available release history at publication time and include the destination and exact revision in its execution authorization. Configure and validate a public consensus observation source capable of proving attestation inclusion and finalized ancestry. If no such independent source is available, duty verification remains pending, not passed. These inputs must be resolved before their dependent execution stages.

## Interactive and recovery behavior

Initial capacity (user-approved 2026-09-14): create three system nodes for the
three anti-affine Vault replicas, one consensus node and one execution node.
Do not require an extra manual scale-up to schedule the initial deployment.
Prysm Beacon, Nethermind and PostgreSQL each target one replica. Signer, validator
client and fence remain at zero only during safe staging; their existing guarded
startup paths target exactly one after custody/readiness/activation checks.
Explicit stop, recovery and fencing operations may still scale to zero.

- Read non-secret defaults from the supported env file; confirm the actual AWS account, Region and deployment identity. Never overwrite GITHUB_TOKEN.
- Apply the [preflight and resume contract](installer-preflight-resume.md): validate sources and permissions, bind state ownership, prepare minimal ECR prerequisites and verify destination digests before VPC/EKS creation. Keep SSM access resources in their separate phase/state.
- Report numbered stages and failures. Preserve state and work directory on failure; refresh and regenerate plans for resume. Do not automatically delete/recreate the deployment or repeat Vault initialization, deposit or signing activation.
- For a new Vault, initialize five recovery shares with threshold three. For existing Vault, inspect and honor its actual initialization and quorum state. Distinguish initialization from an in-progress generate-root ceremony; do not cancel another ceremony silently.
- Write recovery shares to individual permission-restricted files in a private directory, display paths only, and require confirmation of separate secure backup before proceeding. Do not print secret contents into terminal logs, Git or CI. Use the initial root token only for required configuration and revoke it afterwards, including explicit cleanup/recovery handling after failure.
- Reuse an explicitly selected existing validator key only after matching its public key, withdrawal credentials and actual on-chain deposit/status. A keystore file is not proof of deposit. New keys require user-controlled deposit and transaction verification; never send wallet transactions or make duplicate deposits automatically.
- Before reusing an existing signing identity, verify the old signer/client is stopped and slashing protection records are recovered and correctly bound. If the records cannot be recovered safely, infrastructure/node deployment may proceed, but signing must stay disabled pending a separate recovery decision.
  The separately approved [Hoodi missing-history exception](../decisions/2026-09-14-hoodi-missing-history-exception.md) permits an explicit, testnet-only native watermark preparation command. It preserves existing records, verifies the target database and stopped paths, and leaves signing disabled for the normal activation gates. It does not recover historical evidence or guarantee freedom from slashing.
- Gate activation on private execution/consensus readiness, Engine API JWT connectivity, Vault-backed runtime secrets, mTLS, signer/database readiness and the single-signing-path checks. Display the target public key and withdrawal address; require literal `ACTIVATE`. An infrastructure resume must never imply this approval.

## Completion and evidence

Successful activation alone is not completion. Observe attestations for three consecutive assigned epochs after this deployment's explicit activation. Match deployment/release identity, validator public key/index, slot/epoch and attestation data with client/fence/signer activity and canonical chain inclusion. Verify each inclusion is in finalized canonical history using the private Beacon and an independently sourced public chain observation. Merely finalized epochs, signed requests, container health or old validator activity are not proof of these duties.

Pending synchronization, activation eligibility or finality remains pending; missing observations are not success. Persist the observer checkpoint so interruption resumes collection without reactivating or replaying a ceremony. If an epoch fails the success predicate, a later fresh consecutive sequence may qualify; do not combine nonconsecutive successes. Bound individual requests and surface the current waiting reason; do not promise a fixed completion time.

Retain existing release logging/audit delivery requirements, including Vault audit, workload logs and configured AWS collection/storage. Verify delivery with non-secret evidence. Preserve a minimal deployment result and the three duty proofs, not UC reports. Never include recovery shares, root tokens, passwords or private keys. Mark the overall result PASS only when deployment checks, required log delivery and all three finalized duty proofs pass.

## Current gaps, not completed work

For the currently authorized E2E run, the user confirmed all twelve tasks despite omitted numbers in the pasted summary and delegated interactive execution to the agent. Use only `/Users/s1ns3nz0/validator-custody-hoodi-001/validator_keys`; do not generate a new key or deposit. Routine prompts and the gated ACTIVATE step may be answered by the agent under that delegation after their actual prerequisites pass. Record the actor as the delegated agent, not the user. Missing history requires the separately approved exception above; delegation alone does not waive restoration, prove a separate secure backup exists, provide an unknown password or permit fabricated evidence. The distributable installer's normal interactive gates remain intact.

The local Vault digest-alignment tests do not establish live E2E success. Publication-index packaging, verified mirror-receipt production, artifact-first orchestration, full phase recovery, removal of the existing-key-implies-deposit assumption, and post-activation duty completion remain implementation/integration work. Existing helpers should be reused where their contracts fit; their existence is not an acceptance result.
