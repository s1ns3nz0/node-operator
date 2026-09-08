# Security activation clean-room debrief

## Scope and method

This is an independent, clean-room summary of the scoped task bundle
`plans/2026-09-08-security-activation/`, the status report, and the diff from
`290880f1a281ff6d07ac4cbb8eaa1fea8591af0b`. It does not inspect prior task
history, raw plans or scan logs, cloud resources, secrets, or unrelated state.
It makes no deployment, merge, publication, or configuration change.

I read the task contract, plan, graph, evidence, status report, and changed
files. I also reran the focused local checks below against this worktree:

```text
scripts/ci/test-pr-evidence-refresh.sh                 PASS
scripts/ci/test-pr-evidence-check.sh                   PASS
scripts/ci/test-release-source-eligibility.sh          PASS
scripts/ci/test-scm-posture.sh                          PASS
scripts/ci/test-ci-security-evidence-contract.sh       PASS
scripts/ci/test-validator-observability-contract.sh    PASS
git diff --check 290880f1a281ff6d07ac4cbb8eaa1fea8591af0b  PASS (no output)
```

## Observed evidence

### CI implementation

- The diff adds an unprivileged `pull_request_review` signal workflow with no
  permissions and a `workflow_run` handler that loads the refresh script from
  the default-branch SHA. The handler validates signal name, path, event,
  repository, conclusion, and a single PR before it requests a rerun.
- The refresh script looks up the PR's current 40-character head SHA and only
  reruns a completed `pull_request` `ci-security.yml` run for that same PR and
  SHA. The focused fixture test exercises accepted exact-head data and rejects
  an untrusted signal path and a run for another head.
- SCM posture collection now uses each reviewer's latest review on the current
  head. Its test confirms that a later `CHANGES_REQUESTED` state removes a
  previous approval.
- The evidence decision check now records a publisher-run/SHA binding in its
  `external_id`. Release eligibility verifies the trusted workflow run,
  successful completion, exact binding, unexpired exact-SHA artifact, and
  parseable evidence/decision documents with no blocking or approval-required
  result. The focused fixtures include failures for API failure, empty or
  blocked documents, mismatched artifact subject, replayed subject binding,
  wrong publisher, and mismatched check ID.
- Bundle evidence records six local CI checks as passing for commit `883bebd`,
  with an independent Terra review. The clean-room reruns above corroborate the
  changed-script portion locally; they cannot establish GitHub-hosted behavior.

### Scoped infrastructure implementation and asserted live readback

- The Terraform diff separates the Firehose producer KMS permissions into an
  exact-key IAM role policy and makes the encrypted Firehose stream depend on
  it. The focused contract test confirms that dependency and that the policy
  does not depend on the stream, avoiding the identified ordering cycle/race.
- The bundle records passing `terraform validate` and `fmt -check`, a final
  scoped Terraform plan with exit code 0 and no managed changes, and successful
  `harness:check` and `harness:verify`. Those commands were not rerun in this
  debrief.
- The status/evidence reports assert that reviewed, non-destructive changes
  were applied and read back: workload-log retention from 90 to 365 days,
  Firehose CMK and stream encryption, bucket logging/EventBridge settings and
  snapshot multipart-abort lifecycle, plus Terraform-lock-table PITR at a
  35-day recovery period. They also record a bounded Firehose observation of
  successful delivery and no listed KMS errors.

These infrastructure observations are evidence supplied by the completed
bundle, not independently observed by this clean-room review. In particular,
the bounded metric window is transport-health evidence only; it does not prove
complete validator activity coverage or continuing error-free delivery.

## Assessment

The scoped work is **partially complete**. The local CI trust-boundary and
provenance changes, plus the Firehose IAM ordering change, are implemented and
have focused local regression evidence. The supplied AWS readbacks support that
the enumerated safe hardening was applied in the populated `t2` state scope.

It is reasonable to infer that the changes improve fail-closed behavior for
the modeled cases. It is not justified to infer that required checks are active
on GitHub, that release promotion is live, that all AWS roots are reconciled,
or that the project is framework-compliant. The task plan itself distinguishes
implementation from live activation, and the graph leaves hosted activation
pending.

## Remaining risks and activation blockers

- Hosted exact-head positive/negative and post-review-refresh proof has not
  been supplied. Required-check activation must remain pending until a reviewed
  trusted promotion path and those hosted proofs exist.
- GitHub private-repository GitOps protection is blocked by plan/visibility
  restrictions. The task contract does not authorize billing or visibility
  changes.
- Checkov 3.2.522 is not clean: the bundle reports 26 failures and 8 skips.
  The eight named inline skips are absent from the central exception register;
  they must be resolved through supported controls or a separately approved
  service-compatibility decision, not hidden exceptions.
- Bootstrap, foundation, and ops state ownership remains unreconstructed.
  Planning or applying those resources risks creating a duplicate live stack;
  imports/ownership reconstruction are required first.
- Legacy ECR encryption migration/replacement is separately gated. Any
  replacement, downtime, destructive action, or broader state change requires
  a reviewed plan and explicit authorization.
- No private CD/DAST live evidence or end-to-end validator-log completeness
  evidence was provided.
- The synthetic full-history scanner canary demonstrates the local pinned
  scanner/flags detect a redacted historical marker, but it is not hosted PR
  gate proof and must not be treated as such.

## Safe closure state

Keep the change unmerged and do not activate required checks from this evidence
alone. The next authorized decision is review of the trusted handler's
promotion path, followed by hosted exact-head positive/negative and review
refresh proofs. Separately resolve the unregistered scanner skips and
reconstruct the missing state roots before planning any remaining AWS drift.
