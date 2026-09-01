# T-8 PR gates clean-room debrief

## What changed

**Observed:** The scoped worktree changes add an `OPA PR Gate` workflow for `pull_request` events. It checks out the PR head SHA with persisted credentials disabled; declares read-only `contents` and `pull-requests` permissions; pins its actions by commit; collects scanner, formatting, Terraform, and SCM-posture evidence; normalizes it; evaluates OPA; publishes normalized JSON, decision JSON, and SARIF; and makes the workflow fail unless the decision has zero block findings.

**Observed:** The collection path covers Gitleaks, OSV-Scanner, Semgrep, Zizmor, Checkov, `git diff --check`, and offline Terraform validation. Raw reports are placed in a temporary directory. Gitleaks output is reduced to path and rule ID before it becomes an evidence envelope, and the fixture tests assert that a sentinel secret is not retained.

**Observed:** Policy required evidence now includes formatting and Terraform. The policy blocks failed formatting, failed/non-applicable-invalid Terraform results, malformed or absent SCM posture, incomplete required evidence, and Semgrep findings. Tests and fixtures were expanded for these cases. The normalizer validates SCM posture and binds its PR head SHA to the evidence subject SHA.

**Inference:** Taken together, these changes implement the task's intended OPA-governed PR gate with a deliberately non-sensitive artifact boundary, provided the workflow runs successfully in CI.

## Current status

**Observed:** The task contract remains `in_progress`, while the graph records T8-1 through T8-5 as completed and T8-6 (integration and clean-room debrief) as in progress.

**Observed:** The evidence register marks implementation validation `partial`: Bash syntax, collector, normalizer, SCM-posture, publisher, PR-gate fixture, structural graph, and diff checks passed. It also records an independent review with no remaining blocker or high finding.

**Observed:** `npm run harness:check` completed with exit status 0. `npm run harness:verify` is blocked locally because `opa`, `conftest`, and `shellcheck` are unavailable; in-repository fixture checks passed.

**Inference:** The gate is not fully locally validated until the unavailable tool-backed checks run in a suitable environment (normally CI or a prepared developer environment).

## Evidence

**Observed:** The task bundle defines the expected gate outcome, prohibits deployment, publication, merge, secret changes, AWS access, and production access, and requires offline Terraform validation and non-sensitive fixtures.

**Observed:** Workflow inspection shows a final `Enforce OPA decision` step that runs even after an earlier failure. The policy-evaluation step is allowed to continue so the safe output publication can run, then `verify-policy-decision.sh` requires `.summary.block == 0`.

**Observed:** The workflow uploads only published `evidence.json`, `decision.json`, and `policy.sarif`, rather than its raw evidence directory.

**Observed:** The policy and script fixture suite includes a clean result, secret detection/redaction, incomplete OSV evidence, an insecure Checkov finding, an unpinned-workflow Zizmor finding, SCM posture collection, evidence publication, and collector rejection of incomplete scanner output.

**Inference:** The fixtures exercise the primary fail-closed paths and the artifact-safety claim, but they do not substitute for actual execution of the external policy and lint tools.

## Unresolved risks

**Observed:** OPA, Conftest, and ShellCheck were not available locally, so the record contains no successful local executions of the corresponding checks.

**Observed:** The Terraform mirror directory currently contains a contract document. The collector is intentionally fail-closed when Terraform modules exist but a suitable offline provider mirror is absent or incomplete.

**Inference:** Adding Terraform modules will require maintaining reviewed, checksum-verified providers and lockfiles in the offline mirror; otherwise PRs containing those modules will be blocked.

**Inference:** Actual hosted workflow execution remains the outstanding proof that pinned tool installation, GitHub API posture collection, and all scanners interoperate under runner conditions.

## Next decision

Run the complete harness verification in CI or an environment provisioned with OPA, Conftest, and ShellCheck, then record that result and close T8-6 if it passes. If it fails, retain the current fail-closed behavior and address the specific failing integration before declaring the gate complete.
