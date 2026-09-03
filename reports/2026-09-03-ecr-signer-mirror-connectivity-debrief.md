# ECR signer mirror connectivity clean-room debrief

## Scope and method

Fresh Terra review, limited to the completed task bundle, the scoped Terraform,
fixture, output, CI, package, and GitOps documentation diffs, plus the
reported offline validation results. This review made no AWS, ECR, Vault, EKS,
registry, or Terraform-apply call.

## Observed evidence

- `enable_release_signer` and `enable_release_signer_ecr_mirror` both default
  to `false`. The CodeBuild project requires both the enabled mirror and a
  same-account, `ap-northeast-2`, SHA-256-pinned ECR image before it can be
  planned as enabled.
- The mirror foundation declares a KMS-encrypted ECR repository with immutable
  tags and scan-on-push. Its only outputs are the non-secret repository ARN and
  URL.
- The GitHub OIDC trust policy is confined to audience `sts.amazonaws.com` and
  subject `repo:${var.github_repository}:environment:ecr-signer-mirror`. Its
  mirror policy has the ECR authorization token plus the repository-scoped
  layer/manifest upload actions; the checked contract rejects delete,
  repository-policy, lifecycle-policy, and wildcard ECR permissions.
- The CodeBuild service-role policy is distinct from the mirror role: it has
  repository-scoped pull actions (`BatchCheckLayerAvailability`,
  `BatchGetImage`, and `GetDownloadUrlForLayer`) plus its required ECR
  authorization token. The environment uses `SERVICE_ROLE` image-pull
  credentials.
- ECR API, ECR DKR, and S3 private endpoint paths are present. Enabling the
  signer conditionally adds STS and CloudWatch Logs interface endpoints, and
  endpoint ingress for the signer is restricted to its dedicated security
  group on TCP/443.
- The offline fixture enables both flags but uses synthetic account and subnet
  IDs and a digest-shaped ECR reference. Documentation states that it is not
  an apply approval.
- Reported completed checks: `terraform fmt -check`,
  `test:ecr-signer-mirror-contract`, `test:codebuild-release-activation`, the
  enabled offline Terraform plan, `harness:check`, and diff checking. The
  package script exposes the new ECR contract check.

## Inference and operational boundary

The reviewed code establishes a least-privilege, private-image path only; it
does not itself mirror or publish an image. The OIDC trust is an environment
contract, not a GitHub environment, workflow, or role-assumption event.
Likewise, the ECR push identity and CodeBuild ECR pull identity are separate
by policy intent and action set.

No actual ECR mirror, AWS/Vault access, image publication, or Terraform apply
is evidenced by this review. Before any live activation, a separately approved
process must confirm the real account, repository and immutable digest; create
and protect the GitHub `ecr-signer-mirror` environment; validate the deployed
OIDC provider and role trust; use real private subnet IDs; verify ECR API/DKR,
S3, STS, and Logs endpoint reachability; and confirm the private Vault route
and AWS-auth role. A reviewed, read-only live plan remains required before any
apply. No automatic publication is configured or authorized.
