# Single interactive deployment implementation

Baseline: v0.1.20, source a87b02f9422d33e75a20879e5916ff73fe036df5. Status: implementation started; no end-to-end installer completion claimed.

## Verified delivery status

- PR #221 head `9b3e93ef174c60f9079a74391d9bb069127d0980`: CI run
  `34580874828` and Release Images run `34580870792` passed. The Vault
  bootstrap image built successfully; publication was skipped on this branch.
  Local saved-plan, workspace, scope and entrypoint tests passed (34 tests),
  and the committed-source release bundle test passed. This does not prove
  live Vault deployment or authorize applying a plan.
- PR #221 head `54609648a14a2b0c2ed4ac37d0066857d7821f36`: CI run
  `34572077991` passed, including Evidence Contracts after installing the
  missing ripgrep dependency. The trusted decision reported `block=0` and
  `require_approval=1`; passing CI alone does not authorize merge or release.
- Infrastructure preparation/apply adapters have local contract evidence;
  a downloaded-release live infrastructure deployment is not yet verified.
- Task 7 has preparation, guarded plan/apply and private-access verification
  source adapters. Fresh-environment execution and tasks 8-14 remain incomplete.
- PR #221 head `9f9797fbe8af859ba70a8f486854a9422815664e`: CI run
  `34576136851` and Scanner Build job `103188927488` passed. The separate
  trusted decision still requires approval; no release publication is implied.
- No live deployment, Vault ceremony, validator activation or resource
  deletion is evidenced by these local tests.

## Durable decisions

- One public entrypoint, small reusable internal modules. First run, status and resume use the same entrypoint.
- Initial non-secret input: AWS profile, supported Region, deployment name. Discover account, availability zones, endpoints and approved immutable image digests. Ask for validator/custody choices only when needed.
- Use versioned non-secret checkpoints, exclusive execution locks and atomic writes. A checkpoint alone never proves cloud state; reconcile before resume. Never store tokens, private keys, passwords, raw Terraform plans or raw command logs in checkpoints.
- Operations access remains a separate command, Terraform state and apply with explicit confirmation. Do not silently open EKS publicly.
- Vault initialization, key custody, temporary authority, wallet deposit and signing activation require explicit interactive boundaries. Never repeat initialization or deposit on resume or run a second signer for an active key.
- Distinguish infrastructure ready, workloads synchronized, validator activated and new finalized canonical duty verified.
- No Scheduler and no standalone DAST namespace. UC5 stays deferred; UC1-4 require fresh evidence.
- Keep GITHUB_TOKEN unchanged. No silent permissions escalation, automatic deletion or Seoul production mutation.

## Tasks and acceptance criteria

1. **Inventory existing deployment paths.** Document reusable commands, manual handoffs, fixed environment assumptions and missing fresh-install dependencies, with source references.
2. **Define input and completion contracts.** Minimal first prompts, explicit modes and stage-specific mandatory input; invalid inputs rejected before mutation.
3. **Implement one interactive entrypoint.** Start/status/resume work through the same command, with clear pending versus completed stages.
4. **Preflight and discovery.** Check dependencies, authentication, permissions, quotas, naming collisions and release integrity before provisioning; explain unverifiable conditions rather than claiming certainty.
5. **Checkpoint and recovery.** Exclusive lock, atomic non-secret state, interruption handling, context binding, reconciliation and safe rerun tests.
6. **Infrastructure integration.** Provision backend, KMS, network and private EKS in dependency order; feed actual outputs into downstream inputs.
7. **SSM/private access integration.** Separate apply/state with creation confirmation; bounded connection readiness and cleanup; working private EKS/Vault access.
8. **Vault bootstrap and operations.** Fresh init versus existing detection, custody of recovery material, audit/auth/policy configuration and temporary token revocation.
9. **Secrets and rotation.** Complete inventory maps each required secret to Vault path, identity, consumer and rotation sequence; Engine JWT, TLS, signer keystore/password, slashing DB credentials and required deployment credentials included. Validator BLS identity is not an ordinary rotating password.
10. **GitOps and workloads.** Resolve artifact publishing/auth bootstrap, apply Kyverno, pair Nethermind/Prysm Engine API, provision DB/signer/client/Fence and verify readiness and effective access.
11. **Custody, deposit and activation.** Guide key generation/import, withdrawal checks, external wallet submission and waiting/resume; prevent duplicate deposits and double signing.
12. **Completion and logs.** Verify sync, policies, Vault audit/workload log ingestion, then collect finalized duty evidence after guarded activation.
13. **Fault and resume testing.** Expired credentials, missing rights, SSM outage, interruption, partial resources and corrupt checkpoints fail safely and recover without repeating irreversible steps.
14. **Fresh-environment E2E and release.** After scoped Tokyo approval, deploy from downloaded release, collect UC1-4 evidence and publish verified installer version. Protect Seoul and existing active validator custody.

## Delivery slices

- A: Inventory + local input/status/checkpoint path and negative tests (tasks 1-5, partial preflight).
- B: Read-only AWS discovery through infrastructure and separately approved private access (tasks 4,6,7).
- C: Vault and secret provisioning through stopped workloads and audit evidence (tasks 8-10).
- D: Interactive custody through guarded activation and duty evidence (tasks 11-12).
- E: Fault injection, clean release download deployment, UC1-4 and signed installer release (tasks 13-14).

Each slice must demonstrate real behavior through tests. Mock tests do not prove live deployment. Real cloud operations, destructive replacement, credential ceremonies and wallet actions are recorded separately and performed only with the corresponding approval/input.

## Fresh Vault integration prerequisite

Task 8 implementation is in progress, not live-verified. Regional values
rendering, pre-initialization private transport and a sealed-install helper
have 13 passing local mock tests. The 30-check policy-contracts suite and
harness verification passed. The bootstrap image built locally, and its
packaged scripts, template and commands passed a network-disabled smoke check.
Linux rendering and all three network-disabled Terraform bootstrap phase
plans passed. Independent startup/TLS review findings were corrected.
These tests do not prove real Helm deployment, KMS auto-unseal, Pod Identity
or first-init behavior. Installer orchestration and the operator-held
initialization ceremony remain required before this task can be completed.

The entrypoint now accepts `resume --prepare-vault --vault-artifacts FILE`
alongside its normal state/release options, after infrastructure and private
access stages have completed. This operation only prepares private local
inputs. The reviewed artifact file binds account, Region and deployment name
to five digest-pinned images and a chart version/digest. It is not proof of
registry availability, image signature verification, TLS readiness or actual
Vault deployment. Prepared runner inputs deliberately keep cluster-admin
access disabled. Artifact mirroring and guarded execution remain pending.

The pending Vault executor must validate `terraform-work/baseline` and retain
its original `node-operator/baseline/terraform.tfstate` backend identity.
It must not execute providers from the retained original cache: initialize
a fresh verified module copy with the reviewed lockfile and only the validated
backend settings, retaining the same remote state and preserving the original
directory. This needs at least 2 GiB free local space for provider installation.
It must compare the derived foundation network file against the original
handoff and compose the original baseline config with a separate Vault delta.
Do not repurpose `zero apply`, which intentionally rejects temporary Vault
cluster-admin access. Prepare, temporary authority, deployment and revocation
need explicit phase handling and reviewed saved-plan hashes; neither a new
Terraform state nor a silently changed original config is acceptable.

A pure plan-scope validator now distinguishes prepare, grant and revoke.
It rejects unrelated managed mutations, replacements, drift and unresolved
checks. The `--plan-vault` source path connects it to saved preparation
planning after baseline reconciliation. The `--apply-vault` adapter has local
contract evidence (6 executor tests, 24 entrypoint tests, and the 36-check
policy-contracts suite); no live apply is evidenced. A plan check is not
operator authorization. Independent review verified the
fresh-provider-cache boundary and pinned Terraform 1.5.7 JSON compatibility.
Preparation receipts also validate their exact schema, selected deployment,
reviewed hash and type-sensitive scope before publication. Apply still needs
fresh provider initialization, source/backend bindings, terminal confirmation
and post-apply reconciliation; receipt validation alone is not authorization.

The apply command requires `resume --apply-vault --vault-artifacts FILE
--vault-plan-sha SHA256` together with the original state and verified release
directories. It asks for an exact account/Region/deployment/phase/hash phrase
on a terminal. Cancellation starts no apply. Failure and successful runner
provisioning both leave the Vault stage awaiting further work, not complete.
An apply-attempt record must prevent blind retries after an uncertain outcome;
the operator must preserve the state and reconcile remote resources first.
Live saved-plan execution is not yet verified. Tokyo and Seoul bootstrap fixtures have both passed actual
network-disabled Terraform validation and plan generation; this is not live
deployment evidence.

Task 8 cannot be fulfilled by calling a recovery script on an uninitialized
Vault. Existing bootstrap-runner automation deliberately installs sealed Vault
without initialization. The installer must implement a distinct first-init
ceremony with recovery material held by the operator, followed by temporary
administrator revocation and post-init verification. The TLS Secret required
before Vault can serve its own PKI is a bootstrap dependency, not a reason to
place validator signing material in Kubernetes Secrets.

Fresh-install ordering must provision the private cert-manager chart/images
and reconcile `docs/gitops/vault-tls-internal-ca.example.yaml` before invoking
the Vault Helm install. The Vault CodeBuild project now invokes the bundled
`prepare-vault-bootstrap-tls.sh` before Helm: it requires healthy cert-manager,
creates only a missing `vault` namespace, applies the bundled Certificate and
Issuer manifest, waits for both Certificates and checks the Secret name only.
API/RBAC failures and an existing Vault StatefulSet stop it before mutation.
This is a Task 8 platform prerequisite, not work that can wait until Task 10.
Do not export the generated CA/private TLS Secret bytes. The first-init
ceremony is still missing and must be integrated interactively; existing
generate-root recovery wrappers cannot initialize a fresh Vault.
Private cert-manager installation and the CodeBuild invocation/authority
lifecycle still need installer orchestration; this TLS helper does not supply
those dependencies or prove live deployment.

Always pass Region, cluster and SSM instance from the verified handoff into
private transport commands. Existing historical operator-auth scripts contain
Seoul/account-specific defaults and must not be reused unchanged for a fresh
Region. Audit PVC/relay readiness must precede enabling audit devices; key
custody remains a separate interactive ceremony after Vault initialization.
