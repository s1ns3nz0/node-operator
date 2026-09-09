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
