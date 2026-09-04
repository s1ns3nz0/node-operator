# Clean-room debrief: private GitOps source and Vault boundary

## Outcome

Commit `a9868ab4fa292adb81328c8afee293ef2e480316` establishes a versioned
documentation contract and a static contract test. The contract makes private
ECR GitOps repositories the sole Argo CD data-plane source; prohibits direct
`github.com` access from the private VPC; limits a future GitHub App to
repository-scoped `Contents: read` and `Metadata: read`; and defers Vault/VSO
configuration and all credential material to a separately approved task.

No external action, secret creation, deployment, or production access was
observed in the reviewed commit.

## Evidence observed

- The task bundle's contract, plan, and graph match the documented boundary:
  OCI-only Argo CD input, a future least-privilege GitHub App mirror identity,
  and a future namespace-bound VSO delivery path.
- The commit adds only the contract document, its focused static test, and the
  task-bundle records. It does not add an Argo CD Application, repository
  credential, Vault configuration, Kubernetes Secret, or executable external
  integration.
- The document explicitly identifies the future KV v2 path,
  `kv/platform/argocd/repository-credentials`, and Argo CD Secret fields, while
  excluding private-key, token, PAT, deploy-key, and public-network use.
- Independent local checks on 2026-09-04:
  - `bash -n scripts/ci/test-private-source-vault-boundary.sh` — passed.
  - `bash scripts/ci/test-private-source-vault-boundary.sh` — passed.
  - `npm run harness:check` — passed; checked 36 task graphs.
  - `npm run harness:verify` — did not complete successfully (exit 1) because
    local policy prerequisites/evidence are absent: `opa`, `conftest`, and
    `shellcheck` are unavailable, the normalizer fixture
    `policy/tests/fixtures/raw-evidence/incomplete/osv.json` is missing, and
    the PR-gate adapter reports an incomplete OSV JSON report.

## Risks and findings

- The new contract test is not registered in `package.json`; it passed when
  invoked directly, but no package script makes its CI invocation evident from
  this commit. Register or explicitly call it from the applicable CI gate
  before treating it as continuously enforced.
- The document correctly defers sensitive implementation. Before the future
  Vault/VSO task, separately review the exact Vault policy, Kubernetes RBAC,
  VSO `VaultAuth`, Secret lifecycle, encryption-at-rest configuration, and key
  rotation/revocation procedure.
- Policy-adapter verification is currently inadmissible as passing evidence in
  this environment. Its failures are environmental/repository-fixture
  blockers, not evidence that the source-boundary document violates policy.

## Completion support

The reviewed change supports completing the documentation-boundary work and
its direct static validation. It does **not** support claiming policy-adapter
success, nor does it authorize any deferred Vault, GitHub App, Kubernetes
Secret, Argo CD repository credential, or Application implementation. The
task bundle still marks T3 and the task status as `in_progress`; its primary
owner should record this debrief and resolve or explicitly waive the separate
policy-adapter environment gap before marking the task complete.

## Integration disposition

The primary owner subsequently registered the focused test as
`npm run test:private-source-vault-boundary`, reran it successfully with
`npm run harness:check`, and recorded the adapter limitation in the task
evidence. This resolves the registration finding without representing the
unavailable policy adapters as a passing result.
