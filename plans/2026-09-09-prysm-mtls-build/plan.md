# Native Prysm Web3Signer mTLS build

## Authorized completion scope: six remaining workstreams

The user's current goal authorizes all six: remaining runtime image remediation;
reviewed live rollout; singleton validator/fence activation; actual duty and
correlated logs; remaining UC1-5 negative/recovery verification; and PR/CI,
signatures/provenance plus GitOps/remote synchronization. None is complete
merely because a candidate build or draft PR exists. Preserve one identity and
all slashing state; no graph or debrief.

Root owns final integration. Delegated agents reported usage limits, so root
continues locally and records missing independent reviews explicitly. Prepare a
separate publication branch with the cumulative reviewed diff, retaining the
original integration branch and its history. A historical Gitleaks finding in
commit dff3887 is the public KMS resource UUID, not credential material; rename
the ambiguous JSON field and rescan the actual publication history, without
adding scanner exclusions. Start a draft PR for remote feedback; it does not
claim remaining runtime gates or trusted release promotion have passed.

## Source-built node image delivery

After Terra's actual Agent proof review passed, publish only frozen Agent index
33458e87 to its existing private repository. Revalidate the exact candidate,
account, immutable/KMS repository and existing tag before writing; require
registry digest equality and a complete registry rescan afterward. Preserve
the raw Unknown and Medium findings. No rebuild, runtime rollout, Vault token
or trusted CI attestation is included. Root integrates with nearest-tier
fallback; Terra reviews the bounded publication script. No graph/debrief.
An existing equal digest intentionally resumes verification without pushing;
an existing differing digest is refused before authentication. Terra flagged
the distinction from blanket tag refusal; root retains this documented
verified-resume contract to avoid republishing after interrupted observation.

Assess Agent GO-2026-5932 without changing the frozen runtime image. Add an
optional evidence-only BuildKit target deriving from the unchanged builder:
same source, module locks, Go version, platform and minimal tag. Export the
complete go-list package closure and built-binary hash without network in that
step, then require binary hash equality to the frozen runtime before treating
the closure as applicable. Retain the scan finding; absent affected packages
are applicability evidence, not a scanner exclusion or live rollout approval.
Root owns implementation/integration; Terra independently reviews the proof.

The saved three-repository plan is independently reviewed and applied at
backend serial223. Publish only the already full-scanned frozen server and
Injector candidates, with explicit local OCI-index descriptor identity and
exact registry digest equality plus fresh full registry SCA. Use private
task-owned Docker auth without credential helpers, and remove it on exit.
Do not rebuild, overwrite a differing immutable tag, or claim trusted CI
attestation/live deployment. Agent publication remains separate while its
Unknown applicability assessment is unfinished. Keep the two ECR enablement
flags in subsequent reviewed live inputs; do not full-apply reconstructed vars.

CI Quality34303773988 exposed a Linux pipefail regression in the mock operator
recovery test: fake Vault returned without consuming piped capabilities JSON.
Consume stdin in both fake request endpoints instead of suppressing pipefail;
also remove a test-only chmod of the real script so tests run with a read-only
source mount. Real user ceremony files stay unchanged. Verify repeated Linux
Docker execution before publishing the fix.

Prepare separate opt-in Vault server/Agent/Injector ECR repositories using the
existing reviewed source-runtime KMS boundary. Keep upstream-only mirrors,
GitHub permissions, Vault credentials and live workloads unchanged. Require
immutable tags, scan-on-push, enabled key dependency and no automatic deletion.
Root owns IaC and saved-plan execution; Terra independently reviews the exact
three-create delta before any apply. Candidate publication remains separate
from trusted CI promotion and from actual deployment. No graph/debrief.

While the human-held operator ceremony is pending, do not edit or run its
scripts. Close the remaining incomplete scanner evidence for the frozen Agent
and Injector candidates: explicitly include suppressed findings in fresh
reports and require that scanner configuration in their verifiers. Update
the shared Beacon scan config and Nethermind counterpart consistently, without
weakening any finding gate. No new image builds, live credentials or workloads
are needed for this check. Root integrates; Terra reviews the bounded diff.

Next scoped live step: generate a saved targeted Terraform plan for the
operator identity lookup policy, using the canonical backend and current
committed sources in a private temporary directory. Require exactly one
create, no other managed changes, exact Vault role and exact-user GetUser
statement; independently review before applying that saved plan. No Vault
token, root ceremony or workload change is included. Credential env files
must be task-owned0600 and removed on every exit. Read back IAM and backend
metadata and require an allowed exact-user simulation afterward. Root owns
integration/application under the six-stage task authority; Terra reviews the
non-sensitive plan summary only. No graph or debrief.

Prepare operator-only AWS IAM authentication under a separate operator-aws
mount, exact explicitly supplied principal ARN, server-ID replay boundary and
short-lived no-default-policy tokens limited to root-ceremony endpoints. Do
not change the release-signer mount, AWS IAM permissions or live secrets.
Current read-only AWS identity is account106760547719 user/jsyang; do not infer
that this is configured in Vault. User-held recovery shares are required for
the first real configuration. AWS IAM login alone does not establish MFA.
Root owns user-run recovery wrapper and integration; Terra owns only the
configuration helper and its mocked tests. Root remains nearest-tier security
integration owner. No graph/debrief; real login proof is a separate live gate.
Read-only IAM simulation confirms exact-user GetUser is currently denied.
Prepare, but do not apply, an opt-in Terraform policy on the existing Vault
role: one GetUser action and one same-account user ARN. Offline Docker plans
must reject cross-account inputs and verify the enabled policy exactly. The
user-run wrapper checks this prerequisite before asking for recovery shares.
Validate the canonical policy in the retained-Raft real-server fixture and
test wrapper token cleanup using mocks, keeping AWS login as unproven until
the human-held recovery ceremony actually runs.

Transition all seven current recovery ceremonies through a shared read-only
authentication preflight. Vault1 retains its supported share-only flow; Vault2
requires an existing process token or a silent terminal prompt before shares.
Reject sealed, uninitialized, malformed or unsupported status and invalid
authentication without creating a ceremony. Do not store tokens or consume
the share-input stream. Terra owns only the new helper and mocked CLI tests;
root owns wrapper integration, documentation and security decisions using
nearest available tier. Existing production authentication provisioning is
still separate; this change does not mint or configure any live credential.
Root also runs this exact helper through a local CLI bridge to the synthetic
Docker Raft servers, covering real1.x legacy success and real2.x missing,
invalid and scoped-token paths. Keep these actual-server checks distinct from
the fast mocked preflight tests wired into CI Quality.

Root extends the synthetic retained-Raft rehearsal to test the Vault2.1
generate-root authentication transition. On the old synthetic server create
an expiring, non-root, exact-endpoint ceremony token, then verify its survival
after upgrade: missing/invalid tokens fail, the scoped token cannot read KV or
mint tokens, and token plus synthetic share can generate and revoke a root.
No production policy, token or recovery share is accessed. This is a migration
prerequisite, not proof that the user already has a renewable production
authentication path. Root performs integration as the nearest available tier;
Terra reviews the bounded fixture. No graph or debrief.

Rescan the unchanged frozen server with explicit show-suppressed=true, valid
DB, no excludes or fixed-only filtering. Bind the candidate verifier to this
fresh complete report and preserve earlier scans as historical evidence. This
does not imply runtime publication, live HA compatibility or a vulnerability
waiver; the affected-package closure guard remains required.

Root now stages the exact registry-verified Nethermind/Beacon candidates in
GitOps values and its allowlist, with manual-candidate provenance clearly
separate from trusted chart publication. Require before/after render equality
apart from the two image strings, independent review and CI. Both StatefulSets
remain OnDelete with Retain PVCs; no automatic Pod deletion or live application
revision change is part of this staging change.

Live readback found Argo revision0.1.28 absent from ECR. Chart retention counts
all OCI artifacts together (including legacy Cosign tags), allowing deployed
releases to expire. Root owns the exact chart repository lifecycle correction:
one canonical IaC JSON policy expiring only explicit disposable-* tags, after
checking no existing tag matches. No chart/image deletion or recreation. Record
AWS policy readback separately from Terraform backend refresh; do not claim the
missing artifact or Argo sync has been restored by this preventive correction.

GitOps delivery worktree is `/private/tmp/hoodi-gitops-runtime-delivery.xkq2Lv`.
Terra `/root/vault_raft_review` owns only its private-CD chart scanner and
behavioral fixture: remove fixed-only filtering and require valid, unfiltered
evidence, including suppressed matches. Root owns publication workflow, drift
reconciliation and integration. No runtime-image coverage is inferred from
chart SCA. Keep production chart/version unchanged until reviewed delivery.

Root extends the existing isolated Agent compatibility fixture to allow only
the two exact approved server digests (old1.20.4 or candidate2.1), with cached
mock reuse. Exercise actual Kubernetes auth, least-privilege KV rendering and
file-audit HMAC behavior against2.1 without live tokens. This proves neither
production TLS/KMS nor socket relay behavior; preserve these separate gates.

Root owns an isolated Docker Raft rehearsal: fresh synthetic Vault1.20.4
storage, one test unseal share, KV value and snapshot; stop old process before
starting the frozen2.1 candidate on that same task-owned volume. Verify unseal,
retained data and snapshot restoration after a synthetic mutation. No host
ports, live snapshots, credentials or production volumes are allowed. Remove
only returned container/volume IDs on exit. This is compatibility evidence,
not authorization or proof of live HA migration and recovery-token transition.

Root owns live GET-only UC2 TLS-negative verification with the already reviewed
identity-probe image. Fresh zero-client/fence, empty Lease and ready signer
checks are mandatory because probe labels match fence Service selectors. Use
one new synthetic self-signed TLS Secret; project real credentials by Secret
reference only, never read them locally. Exercise good control, bad server CA,
untrusted client certificate, and good post-control with identical networking.
Remove only task-owned Pods/Secret using UID preconditions, verify absence and
unchanged NetworkPolicies. This proves transport denial, not actual duty or
completion of the still-vulnerable full runtime inventory.

Provision a separate `aws_ecr_repository.upcheck_runtime[0]` under the existing
node-runtime KMS boundary, with a reviewed one-create targeted plan. Publish
the already scanned Python candidate by digest. Before any Nethermind proxy
rollout, revalidate exact Deployment UID/image/replica state and manager/Argo
ownership, preserve the current Python code and NetworkPolicies, then require
rollout readiness and actual GET/denied-route tests. Do not apply this image-only
rollout to the signer proxy with its unresolved mTLS health contract.

Root owns `.ci/upcheck-python-runtime/` as a runtime-only replacement candidate
for the full ZAP image currently used to execute Python health proxies. Preserve
Python stdlib functionality and verify exact Python/SSL versions, nonroot
read-only execution and image scan. Do not call this end-to-end proxy repair:
the signer proxy's stale hostname/mTLS/fence route is a separate live contract
that must be resolved before rollout, without handing signing credentials to
DAST. The scanner job's ZAP image remains separately scoped.

Root owns `.ci/vault-server-hardened/` as a candidate-only full Vault2.1 source
build. Reuse verified Agent source/toolchain/module checksums but build the full
upstream CLI/server (no minimal feature tag). Exercise generate-root and Raft
snapshot-inspection command tests, retain complete build/dependency metadata,
then require final-image scanning and isolated Raft rehearsal. This authorizes
no automatic live2.1 upgrade: recovery-token transition, backup/restore and
mixed-version rollout constraints must be resolved first. Keep all live secrets
and production Raft data out of Docker build/test contexts.

Root also owns `.ci/vault-k8s-hardened/`: official injector1.7.6 still scans
C4/H30, limited to Go1.26.5, x/crypto0.54 and OpenSSL3.5.7. Pin upstream
commit fbc5b1f0cd4d1c7dd5a8830e32c8ed636d7318d7, use Go1.26.6 and
x/crypto0.56, and patched runtime libraries. Execute upstream unit tests in
Docker, retain final module inventories and license, then scan the exact image.
Do not publish or apply it merely because the build passes; generated admission
behavior and live compatibility remain separate gates. No Vault waiver.

Root owns `infra/terraform/node-runtime-ecr.tf`: separately opt-in immutable
Nethermind/Beacon repositories and a dedicated rotating KMS key. Preserve the
existing upstream-only mirror and GitHub trust/publisher permissions. First
validate a targeted Docker Terraform plan against the canonical backend and
review the exact resource delta; do not apply unrelated reconstructed inputs.
Only publish already verified immutable candidates after repository readback.
Manual candidate publication remains distinct from trusted CI promotion.

1. Resolve v7.1.8 to its immutable commit and inspect upstream call sites/build.
2. Add a small maintained patch with dedicated HTTP TLS flags, strict input
   validation and synthetic positive/negative transport tests. Keep existing
   gRPC flags separate and preserve default upstream behavior when unused.
3. Pin source and toolchain; apply with checked context, build and test the
   patched client. Do not claim success from text-only contract assertions.
4. Prepare reviewed image provenance and deployment input changes. Live
   certificate provisioning, exact-digest publication and startup are separate
   reviewed gates; retain existing BLS identity and slashing history.

Root owns build integration and this bundle. Sol owns upstream patch security
review and delegates isolated patch implementation to Terra if needed. Work
must not overlap root build files. No graph or debrief is produced.

User follow-up: repeated builds and tests run in Docker wherever practical.
Use `scripts/ci/build-validator-images.sh [prysm|fence|web3signer|identity-probe|all]` for the Linux
release path; host-native source verification is diagnostic only. Reuse
BuildKit module/compiler caches without routinely pruning them. Publish and
deploy the already scanned image by immutable digest, never rebuild during
deployment. Build success alone does not satisfy the vulnerability gate.

The shared builder also supports `beacon`, `audit-relay`, and `nethermind`.
Validate an already built Beacon without rebuilding with
`scripts/ci/verify-prysm-beacon-image.sh IMAGE NEW_SCAN_JSON`. This freezes the
local image ID, executes isolated runtime checks and scans all findings. It
does not automatically waive Unknown findings or establish live compatibility.

Latest user authorization permits residual Prysm-library risks after maximal
feasible remediation and a per-finding assessment retained as PR evidence.
Follow `docs/operations/prysm-risk-acceptance.md`; no exceptions are accepted
yet and generic release gates must not be weakened globally.

## Runtime remediation dependency

Fresh scan found the deployed Web3Signer 26.4.2 image at Critical 2/High 51.
The official same-version distroless candidate is worse (Critical 3/High 59).
Retain application version and signing/slashing behavior; prepare a minimal
upstream dependency patch and patched JDK/runtime container. Root owns Docker
integration; Terra agent prysm_dependency_patch owns only the isolated
Web3Signer dependency patch and source lock. No signer vulnerability waiver.
Require actual image scans/tests and retained-DB compatibility before rollout.
The independent GET-only mTLS probe is owned by credential_validator_integration
under cmd/validator-signer-identity-probe and its .ci Dockerfiles; root owns
cluster orchestration. Neither task may read real custody or deploy itself.

## Retained slashing data rehearsal

User-delegated in-scope maintenance authorization covers stopping only the
hoodi-001 signing path and DB for a consistent encrypted backup. Re-read exact
UIDs, zero-client state and controller ownership before any stop. Preserve the
original PVC/PV and EBS volume; do not invoke the old broad schema-migration
script because its Lease reset does not meet the current guarded handover.
Use an encrypted EBS snapshot and isolated clone (snapshot CRDs are not
currently advertised). The clone must not match existing Service selectors,
must have no Vault credentials or service-account token, and must not expose
the DB over a network. Validate PostgreSQL16.15/control state, preserved data,
collation/index handling for glibc2.36 to2.39, clean restarts and recovery before
any original-volume image change. Failed rehearsal leaves original data intact.
Only change a Deployment template through the reviewed UID/RV CAS helper;
Lease release remains a separate expired-holder, stopped-Pod gate.

## Current verification sequence

The original DB upgrade, singleton signer public-key mTLS check, guarded Lease
release and zero-replica client/fence staging are complete. Live GET-only
network probes also passed: fence-labelled control succeeds, client-labelled
direct access fails, and both owned Pods were removed with policies unchanged.
This does not complete the continuous fence or actual-duty scenarios.

Remaining order: remediate and scan the injected Vault Agent, inventory other
running node/custody/logging images, validate agent/server compatibility and
runtime security independently, then recheck private chain activation before
starting the sole client/fence. Never apply the Prysm exception to Vault or
other images. Luna runtime_image_inventory owns read-only exact-image scans;
Sol credential_validator_integration and its isolated Terra worker own the
agent-only source build/tests. Root integrates runtime and Terraform evidence.
No model fallback, graph or debrief is used for these subtasks.

Fresh runtime inventory expands the required remediation beyond the initial
signing containers: Nethermind C0/H1, Beacon C5/H43, audit relay C3/H53,
injector C20/H122 and ZAP-based health proxies C66/H327. These are artifact
findings, not evidence of exploitation. Do not claim zero findings from a
validator-client-only scan.

For Nethermind, preserve the exact approved 1.39.3 application files and
replace only its framework-dependent runtime with pinned official ASP.NET
10.0.11 resolute-chiseled. Upstream commit
`28cbe2a0ae28373f66abdc584f3eaf21516e84b3` publishes with
`--no-self-contained`, so this avoids the unrelated 2.0 release candidate.
Root owns `.ci/nethermind-runtime/`, exact application-byte comparison,
runtime/version smoke and final-image scan. No live node change until these
checks pass and the retained node-volume/restart boundary is reviewed.

For Beacon, first inspect the approved v7.1.8 binary's dynamic-library and
SBOM coverage. Its current Critical/High matches are Debian11 OS packages.
A supported runtime-only rebase may preserve the exact beacon binary, but an
empty Go catalog must not be mistaken for clean dependencies. Terra may own
`.ci/prysm-beacon-runtime/` and its isolated runtime test; if original Go
metadata is absent, escalate for source/dependency evidence or a reviewed
source build before declaring the full artifact acceptable.
