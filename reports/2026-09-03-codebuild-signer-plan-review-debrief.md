# Clean-room debrief: CodeBuild signer enabled-plan review

## Review conclusion

The supplied evidence supports an **offline configuration review only**. It
does not support a live Terraform plan, an apply approval, or enabling the
release signer.

## Observed evidence

- The task contract prohibits Terraform apply and cloud, Vault, EKS, and secret
  access. Its expected outcome is an offline enabled-signer plan with explicit
  live-state requirements.
- The enabled fixture sets `offline_validation = true` and contains the
  synthetic account ID `123456789012` and deliberately fake subnet IDs. It
  pins the reviewed GHCR signer image by SHA-256 digest.
- The offline validator copies the module to a temporary directory, removes
  `backend.tf`, runs `terraform init -backend=false`, and runs
  `terraform plan -refresh=false` with synthetic credentials. It therefore
  does not read a configured backend or refresh provider-managed state.
- The enabled-plan test invokes that validator and asserts creation of
  `aws_codebuild_project.release_signer[0]`; it also rejects creates of NAT or
  Internet gateways and a created resource with `public_access=true`.
- The supplied evidence records these passed checks: enabled signer plan (149
  creates, signer project present, and no NAT/IGW/public access), baseline
  offline plan (99 creates), signer activation contract, harness check, and
  whitespace diff check. These are reported results; they were not rerun in
  this clean-room review.

## Why this is not a live apply plan

This plan intentionally has no backend state, API refresh, or deployed-network
validation. In particular, its subnet IDs are synthetic, so it cannot establish
that they exist, belong to the target VPC, or are the baseline deployment's
private subnets. A live, read-only plan first needs the approved backend, the
actual account ID, and `release_signer_subnet_ids` from the deployed baseline's
`private_subnet_ids` output. That is a prerequisite review, not authorization
to apply.

## GHCR networking blocker and recommended resolution

The reviewed documentation states that the signer CodeBuild project is
private-only, permits HTTPS only inside the VPC CIDR, and has no NAT route,
while the configured image is hosted on external GHCR. It cites the exact AWS
CodeBuild documents [VPC support](https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html)
and [Troubleshooting CodeBuild](https://docs.aws.amazon.com/codebuild/latest/userguide/troubleshooting.html):
VPC builds need a NAT path to reach public endpoints, and the custom-image
guidance recommends an in-Region Amazon ECR image when image pulls fail.

Therefore, the current GHCR reference is a live-build blocker under the
private-only boundary. The recommended design is to mirror the reviewed signer
image to a private Amazon ECR repository in `ap-northeast-2`, pin the ECR image
digest, and retain the existing private ECR API, ECR DKR, and S3 endpoints.
Before a live plan, also verify the private endpoints required by actual build
calls, including STS for Vault AWS authentication and CloudWatch Logs for
encrypted logs. This recommendation is an inference from the reviewed network
boundary and the cited AWS guidance; no network or cloud access occurred in
this review.

## Clean-room boundary

I reviewed only the supplied task bundle, listed relevant files and diffs, and
the recorded check outcomes. No Terraform, AWS, Vault, EKS, production, or
external action was performed.
