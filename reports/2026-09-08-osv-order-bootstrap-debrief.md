# OSV order bootstrap clean-room debrief

Reviewed clean-room scope: task bundle `plans/2026-09-08-osv-order-bootstrap/`, the bounded `origin/main...HEAD` diff at supplied PR 128 head `04d15cc0a7ac9c63b22903e193d89ba9de7e617f`, and focused local checks in `/private/tmp/node-operator-osv-order-bootstrap`.

## Result

No blocking defect found in the bounded change. The configured OSV Scanner invocation now uses the v2.4-compatible command order:

```sh
osv-scanner scan source --config="$OSV_CONFIG_FILE" --no-ignore --format=json "$source_directory"
```

The sole behavior change is moving `scan source` ahead of the config option. The focused contract was changed in lockstep, so it will fail if that intended ordering regresses. No unrelated implementation files changed; the remaining five changed files are this task's contract, plan, graph, and evidence records.

## Observed

- The supplied checkout resolves to `04d15cc0a7ac9c63b22903e193d89ba9de7e617f`.
- `git diff --check origin/main...HEAD` passed.
- `scripts/ci/test-ci-security-evidence-contract.sh` passed in the supplied checkout.
- Task-bundle evidence records passed focused collector and script-quality checks, harness check and verify, and its documented pinned-image reproduction: the old order failed by treating `scan` as a source path, while the corrected v2.4 order completed with zero results.
- Supplied hosted observation: policy-quality scanners and Terraform policy-foundation build succeeded; publish was skipped. The CI Evidence Decision failed because it still used the old immutable scanner-image digest.

## Inferred assessment

- The patch is a narrowly scoped, appropriate prerequisite for producing a corrected scanner image through the normal reviewed-main build path.
- The hosted CI Evidence Decision failure is consistent with the task bundle's stated activation sequence and is not evidence that this source correction failed.
- That failure does **not** authorize a waiver: the old immutable image remains in use until a reviewed merge triggers the automatic main image build, its resulting digest is verified, and a separate workflow pin-promotion change is reviewed.

## Deployment and authority

Deployment/promotion is not done. This review performed no merge, image publication, workflow-pin update, cloud mutation, secret access, push, or other external operation. The task bundle assigns Sol (`/root/ci_optimization`) as integration owner; any activation remains with that owner under the documented sequence.
