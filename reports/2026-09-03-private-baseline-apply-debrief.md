# Clean-room debrief: private baseline apply

## Scope and independence

This Terra review considered the completed task bundle in
`plans/2026-09-03-private-baseline-apply/`, the current Terraform diff, and
the local checks listed below. It made no AWS, Kubernetes, Terraform-backend,
registry, Vault, GitHub, or other external call. This report does not
authorize further changes.

## Observations

- The task contract restricts the work to the initial private baseline and
  explicitly excludes release/ECR actions, Vault initialization or unseal,
  workload deployment, secret changes, and access outside the approved
  account. It records the narrowly approved node-group and stranded EBS CSI
  add-on replacements.
- The final non-sensitive evidence records a full pinned-image Terraform plan
  with detailed exit code `0`. It also records an `ACTIVE`, issue-free managed
  node group and `ACTIVE` vpc-cni, EKS Pod Identity Agent, and EBS CSI
  add-ons. These are execution records supplied by the primary integration
  task, not observations independently reproduced by this reviewer.
- The Terraform diff declares vpc-cni before the managed node group. It adds
  the EKS Pod Identity Agent and makes EBS CSI depend on the node group, that
  agent, and the EBS CSI Pod Identity association. This dependency graph is
  consistent with the recorded recovery of the EBS CSI add-on.
- Node egress remains VPC-scoped, with an additional TCP/443 rule using the
  AWS-managed S3 prefix list. The stated intent is private S3 gateway traffic
  required for image-layer retrieval; the diff does not add an internet
  gateway, NAT gateway, or public node address.
- The EBS KMS policy grants the Auto Scaling service-linked role only the
  cryptographic actions required for encrypted launch-template volumes and a
  resource-grant-limited `CreateGrant`. The policy also retains the separate
  EBS CSI Pod Identity grant condition.
- The audit changes remove an AWS Config reserved S3 key prefix and remove an
  incompatible CloudTrail encryption-context condition from the notification
  key policy.
- The final evidence records removal of the temporary log-filtering and STS
  decode permissions, leaving only `sts:GetCallerIdentity` in the referenced
  caller-identity statement.

## Local validation

- `jq empty` for the task contract, graph, and evidence: pass.
- `terraform -chdir=infra/terraform fmt -check -recursive`: pass.
- `git diff --check`: pass.
- `npm run harness:check`: pass; it structurally checked 32 task graphs.
- `npm run harness:verify`: structural check passed, but policy adapters did
  not complete because `opa`, `conftest`, and `shellcheck` are unavailable and
  the OSV fixture is intentionally incomplete. This is a local tooling/fixture
  limitation, not evidence of a Terraform or AWS policy failure.

## Inference and conclusion

Taken together, the task contract, implementation diff, recorded runtime
verification, and zero-change final plan support the conclusion that the
approved private-baseline recovery has converged without expanding into the
prohibited release, ECR, Vault, or workload scopes. The retained limitations
are that this clean-room reviewer did not independently query AWS and that the
optional local policy adapters were unavailable; future changes should rerun
those adapters in a provisioned validation image or CI environment.
