# Approval and execution log

This log records execution decisions for the dynamic CI/CD and Hoodi node
program. It contains only non-sensitive metadata; it must never contain tokens,
endpoint URLs, certificates, secret values, raw scanner output, or kubeconfig
data.

## 2026-09-04 — private CD prerequisite preparation

| Decision point | Recommended execution | Action taken | Evidence / outcome |
| --- | --- | --- | --- |
| GitHub release boundary | Require release-environment approval, block self-approval and administrator bypass, and protect release tags. | Created the `release` Environment, required reviewers, protected-branch policy, and a SemVer tag ruleset. | Remote readback is recorded in the task evidence. |
| GitHub-to-AWS runner connection | Use a repository-scoped AWS CodeConnections GitHub connection rather than a stored runner token. | Created `node-operator-private-runner`, imported it as the CodeBuild GitHub App credential, and granted only connection-use/token-read permissions to the runner role. | Connection status is `AVAILABLE`; no token was stored in the repository. |
| Dedicated CodeBuild runner and webhook | Create a repository-scoped ephemeral runner and accept only queued workflow jobs. | Created `node-operator-baseline-private-release` with the CodeBuild GitHub Actions runner buildspec and an active `WORKFLOW_JOB_QUEUED` webhook. | A non-VPC smoke workflow completed successfully. |
| Temporary self-approval for VPC runner smoke | Permit self-review only long enough to release one manually dispatched connectivity test, then restore the protection. | Set `prevent_self_review=false` and approved the one pending `release` deployment for the smoke run. | Approval applies to the single smoke deployment; it is not a substitute for the normal release gate. |
| Private runner network path | Keep EKS private and add outbound-only egress for the runner, because GitHub Actions runner registration cannot use AWS PrivateLink. | Created an IGW, a dedicated small public NAT subnet and route table, and a single NAT gateway. The private workload subnets retain no public IP assignment. | NAT availability, private default route, and runner smoke result will be read back before this row is treated as complete. |

## Operating rule for later tasks

For every approval-dependent action, append the decision point, bounded action,
actual action, and non-sensitive evidence. A rejected, unavailable, or pending
approval is recorded as a prerequisite failure, never converted into a manual
pass.
