# Approval and execution log

This log records each point where an execution decision was required during the
dynamic CI/CD and Hoodi node program. It contains only non-sensitive metadata;
it must never contain tokens, endpoint URLs, certificates, secret values, raw
scanner output, or kubeconfig data.

## 2026-09-04 — private CD prerequisite preparation

| Decision point | Recommended execution | Action taken | Evidence / outcome |
| --- | --- | --- | --- |
| GitHub release boundary | Require an Environment approval, block self-approval and administrator bypass, and protect release tags. | Created the `release` Environment; enabled a required reviewer, self-review prevention, protected-branch policy, and a SemVer tag ruleset. | Remote readback recorded in `plans/2026-09-04-private-cd-prerequisites/evidence.json`. |
| GitHub-to-AWS runner connection | Use a repository-scoped AWS CodeConnections GitHub connection rather than a stored runner token. | Created `node-operator-private-release`; the operator completed the GitHub App authorization. | Connection status changed from `PENDING` to `AVAILABLE`; no token was stored in this repository. |
| Dedicated CodeBuild runner creation | Create a repository-scoped ephemeral CodeBuild runner with only log-write and connection-use permissions. | Created the dedicated CodeBuild service role and granted its connection-use action only for `node-operator-private-release`. The creating principal received the same single-connection action after the first API denial. | Project creation remains denied by CodeBuild with `OAuthProviderException`; the GitHub App connection is available but its repository authorization is not accepted by the CodeBuild source-provider API. No runner project, webhook, or deployment was created. |
| Private runner network path | Preserve the no-NAT/no-public-egress VPC baseline. Add only a reviewed, destination-allowlisted private HTTPS egress path before creating a runner that must communicate with GitHub Actions. | No NAT, internet gateway, public route, or permissive runner was created. | VPC route and endpoint readback showed only private VPC routes, S3 gateway access, and AWS interface endpoints. A CodeBuild Actions runner cannot yet be validated from this VPC. |

## Operating rule for later tasks

For each approval-dependent action, append an entry before execution with the
decision point, recommended bounded action, actual action, and non-sensitive
evidence. A rejected, unavailable, or pending approval is recorded as a failed
prerequisite, not converted into a manual pass.
