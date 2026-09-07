# Clean-room debrief: signer ECR mirror delivery

Task: `2026-09-05-signer-ecr-mirror-delivery`  
Reviewer: independent clean-room reviewer  
Disposition: **blocked for final delivery acceptance; do not dispatch or publish until the bundle is repaired and the role boundary is independently evidenced.**

## Scope and observed evidence

Read-only review covered only the task bundle,
`.github/workflows/ecr-signer-mirror.yml`, and
`scripts/ci/test-ecr-signer-mirror-contract.sh`. No AWS, GitHub environment,
secret, image-registry, or remote-state access occurred.

- `bash scripts/ci/test-ecr-signer-mirror-contract.sh` passed.
- `git diff --check HEAD -- <reviewed paths>` passed; the relevant delivery
  commit is `451f078c9c8ecb63f266409709677e44d2d213f2`.
- `npm run harness:check` failed: the task `graph.json` is invalid. It lacks
  `task_id`, uses string nodes rather than nodes with `id`, and uses tuple
  edges rather than `from`/`to` edges. The required `evidence.json` is also
  absent from this task bundle.

## Security review

The workflow has no hard-coded credentials or static secrets. It uses the
GitHub token only through `docker login --password-stdin`, obtains a short
lived OIDC token, and writes temporary STS credentials to `GITHUB_ENV` without
printing their values. `contents: read`, `packages: read`, and `id-token:
write` are the minimal declared GitHub permissions apparent for checkout,
private GHCR pull, and OIDC. The raw OIDC exchange does mean the temporary AWS
credentials are available to later job steps; that is normal for this pattern,
and the hosted runner is ephemeral.

Source selection is fail-closed in the reviewed YAML: it accepts only
`ghcr.io/s1ns3nz0/node-operator/vault-release-signer@sha256:<64 lowercase hex>`.
Tags and other registries/repositories are rejected. The destination repository
and region are literals, and the pushed tag is derived from the source digest.

The destination registry account remains a protected-environment variable
(`AWS_ACCOUNT_ID`) that is tested only for non-emptiness. More importantly, the
workflow itself cannot prove that `ECR_SIGNER_MIRROR_ROLE_ARN` trusts only this
repository/environment or that its IAM policy grants push only to that one ECR
repository. The structural test searches the Terraform source for fragments,
but that Terraform trust/policy document and an applied-plan result were not
part of this clean-room scope. Thus OIDC least privilege is **plausible from
the workflow configuration but not independently established by this bundle**.

The workflow also treats any digest in the allowed GHCR repository as
“approved.” A protected environment may provide human approval, but reviewer
requirements and an approved-digest allowlist are configuration/external
controls not evidenced here. This is a residual source-approval gap if
repository membership alone is not the intended approval boundary.

## Required remediation before reconsideration

1. Repair `graph.json` to the harness schema and add `evidence.json` recording
   the actual validation commands/results; rerun `npm run harness:check`.
2. Include the exact OIDC trust policy and mirror-role IAM policy (or a
   non-sensitive, validated plan excerpt) in the task evidence. Demonstrate
   `aud=sts.amazonaws.com`, repository plus protected-environment subject
   restriction, and a single destination repository push boundary.
3. If protected-environment review is not the intended approval mechanism,
   enforce an approved digest/provenance allowlist and test its rejection path.

The passing contract test is useful structural evidence, and the reviewed
workflow avoids direct secret exposure. It is not sufficient evidence for
final delivery acceptance while the required task graph/evidence is invalid or
missing and the decisive AWS trust boundary is outside the reviewed bundle.

## Addendum: repaired task bundle

Follow-up review observed that `plans/2026-09-05-signer-ecr-mirror-delivery/
graph.json` was repaired and `evidence.json` was added. `npm run
harness:check` now passes, checking 50 task graphs. The evidence file records
passing harness, mirror-contract, script-quality, and whitespace checks and
states the intended OIDC audience, environment subject, single-repository
scope, and no-live-execution boundary. This clears the earlier harness/bundle
blocker. It does **not** independently verify the Terraform trust policy or
live AWS role behavior; the OIDC/live-apply limitation above remains.
