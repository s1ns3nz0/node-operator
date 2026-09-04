# Private CD prerequisite debrief

## Conclusion

The reviewed source changes are safe to retain as a fail-closed prerequisite
boundary, but the task's expected outcome is **not complete**. The CodeBuild
GitHub connection is pending operator completion and there is no dedicated
CodeBuild GitHub Actions runner project or `WORKFLOW_JOB_QUEUED` webhook. A
release job using the new label therefore cannot be scheduled or dynamically
verified.

## Observed evidence

- The uncommitted diff against `origin/main` changes only the release workflow,
  private-runner contract, targeted contract tests, package script, and this
  task bundle. It introduces no secret, endpoint, public-network, deployment,
  or artifact-publication value.
- The release job now requires the exact ephemeral private CodeBuild runner
  label and the protected `release` environment. It no longer selects a
  GitHub-hosted runner. Its existing required role and artifact-bucket inputs
  remain fail-closed when unset.
- Task evidence records successful non-sensitive readback of the protected
  GitHub release environment, main/tag protection, and private-only active EKS
  control-plane posture.
- Task evidence records the CodeConnections entry as `PENDING`, and explicitly
  records that no GitHub Actions runner project or `WORKFLOW_JOB_QUEUED`
  webhook exists. Existing CodeBuild projects are documented as `NO_SOURCE`
  bootstrap executors, not Actions runners.
- Independent local reruns passed: `npm run test:release-private-runner-gate`,
  `npm run test:vault-private-release-runner-contract`, `npm run
  test:codebuild-release-activation`, `npm run harness:check` (49 graphs),
  and `git diff --check`.
- `npm run harness:verify` exited successfully. Its adapter output includes
  expected insecure-fixture policy denials, ShellCheck informational SC2016
  notices, and an `osv produced an incomplete JSON report` diagnostic; it is
  not evidence of an actual hosted release run or a completed OSV report.

## Inference and limits

The exact runner label, environment gate, and unset-required-input checks make
the source path conservative: it cannot silently fall back to a public
GitHub-hosted runner and it cannot proceed through its existing credential
checks with empty inputs. This supports a safe source-only prerequisite change,
not readiness for deployment.

GitHub protection and EKS posture readbacks support the stated boundary, but
do not prove runner-group restriction, CodeConnections authorization,
CodeBuild webhook delivery, private Vault/registry/observability reachability,
or end-to-end release execution.

## Blockers before task completion

1. An operator must complete the pending GitHub CodeConnections authorization.
2. A reviewed, dedicated private CodeBuild GitHub Actions runner project must
   be created and restricted to this repository.
3. Its `WORKFLOW_JOB_QUEUED` webhook must be configured and read back.
4. The required private runner, signer-role, artifact-bucket, Vault, registry,
   and observability prerequisites need non-sensitive readback from that actual
   runner path, followed by a separately authorized dynamic verification.

No cloud, GitHub, deployment, secret, publication, or push action was taken by
this reviewer.
