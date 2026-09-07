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
| Private service-path smoke permissions | Grant only the API actions necessary to verify runner identity, private EKS reachability, ECR authentication, and CodeBuild log-group discovery. | Added `eks:DescribeCluster` for `node-operator`, `ecr:GetAuthorizationToken`, and `logs:DescribeLogGroups` to the dedicated CodeBuild runner role; executed the same commands in the private CodeBuild project. | The VPC build completed successfully. The workflow check is committed and awaits protected-PR merge before it becomes recurring evidence. |
| Post-merge private runner smoke | Verify the merged GitHub workflow pulls the reviewed release-build digest and reaches its approved private AWS paths. | Temporarily allowed self-review for one manual `release` smoke deployment, approved it, and immediately restored self-review prevention. | The GitHub Actions job and its CodeBuild runner build both succeeded; image pull, EKS, ECR, and CloudWatch checks passed. |
| Temporary self-approval for VPC runner smoke | Permit self-review only long enough to release one manually dispatched connectivity test, then restore the protection. | Set `prevent_self_review=false`, approved the one pending `release` deployment, then restored `prevent_self_review=true` immediately after completion. | The approved run completed successfully; the normal release gate is again enforced. |
| Private runner network path | Keep EKS private and add outbound-only egress for the runner, because GitHub Actions runner registration cannot use AWS PrivateLink. | Created an IGW, a dedicated small public NAT subnet and route table, one NAT gateway, a private-subnet default route to that NAT, and runner security-group TCP/443 egress. The private workload subnets retain no public IP assignment. | The post-change CodeBuild runner build and GitHub smoke job both succeeded. EKS remains private-endpoint only. |
| Raw evidence retention and access control | Retain only non-sensitive digest-bound summaries; never publish raw DAST captures, certificate material, scanner candidates, or telemetry payloads. | Added the private-CD evidence retention contract. | A runtime telemetry service is explicitly still a later approval-dependent prerequisite. |
| Release signer image prerequisite | Use a reviewed, same-account private-ECR digest for the signer build. | Checked the GitHub package API and private ECR repository state without modifying credentials. | The current CLI token lacks `read:packages` and the private signer repository is absent; image mirroring remains a recorded prerequisite. |
| Vault bootstrap readiness diagnostics | Allow the private bootstrap executor to read only Pod/PVC/event state in the `vault` namespace so it can verify its own rollout. | Associated the EKS namespace-scoped `AmazonEKSViewPolicy` with the dedicated Vault bootstrap role and ran read-only diagnostics. | EKS API, encrypted PVCs, and one Vault Pod are reachable; the Vault cluster remains uninitialized and sealed, so replicas are correctly not Ready. |
| Vault initialization | Initialize the KMS-sealed Vault HA cluster and place recovery/root material in an approved secret-management process. | Not executed. | This operation creates secret material and needs explicit secret-handling authorization; it cannot be replaced with a readiness bypass or manual pass. |
| Signer ECR mirror live plan | Enable only the conditional signer-mirror resources from a state-aligned Terraform input set. | Ran a read-only plan with the mirror flag; did not apply it. | The plan exposed 32 unrelated destroys from stale optional state/default-input mismatch and KMS `DescribeKey` denials for the current principal. A targeted or incomplete plan is not an apply basis. |

## Operating rule for later tasks

For every approval-dependent action, append the decision point, bounded action,
actual action, and non-sensitive evidence. A rejected, unavailable, or pending
approval is recorded as a prerequisite failure, never converted into a manual
pass.
