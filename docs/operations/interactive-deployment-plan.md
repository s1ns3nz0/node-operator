# Single interactive deployment implementation

Baseline: v0.1.20, source a87b02f9422d33e75a20879e5916ff73fe036df5. Status: implementation started; no end-to-end installer completion claimed.

## Verified delivery status

- PR #221 head `54609648a14a2b0c2ed4ac37d0066857d7821f36`: CI run
  `34572077991` passed, including Evidence Contracts after installing the
  missing ripgrep dependency. The trusted decision reported `block=0` and
  `require_approval=1`; passing CI alone does not authorize merge or release.
- Infrastructure preparation/apply adapters have local contract evidence;
  a downloaded-release live infrastructure deployment is not yet verified.
- Task 7 is being connected as a separate input-preparation operation.
  SSM plan/apply, private-session readiness and tasks 8-14 remain incomplete.
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
