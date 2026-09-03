# CodeBuild signer enabled-plan review

The reproducible offline review uses
`fixtures/offline-release-signer.tfvars`. It is deliberately non-secret and
sets `offline_validation=true`; its account ID and subnet IDs are synthetic.
Run it with:

```sh
npm run test:codebuild-signer-enabled-plan
```

The reviewed configuration pins the signer image to:

```text
ghcr.io/s1ns3nz0/node-operator/vault-release-signer@sha256:3674b70a8c02a7fd0734e8e0d7c7f4f33fe7701f30b4c6f21569877721d55d07
```

## Offline result

The enabled synthetic plan creates 149 resources. It includes the CodeBuild
signer project, its private security group, encrypted signer log group, three
dedicated KMS keys, and encrypted/versioned release artifact buckets plus a
replica. The plan boundary check found no NAT gateway, Internet gateway, or
resource with `public_access=true`.

This result is a configuration review only. It uses no backend, refresh, AWS
provider API, deployed subnet, or live state. It is not an apply approval and
does not prove that the synthetic subnet IDs exist.

## Live-plan inputs and blockers

A controlled, read-only AWS plan must use the approved backend and the actual
account ID. `release_signer_subnet_ids` must come from the deployed baseline
state's `private_subnet_ids` output, not this fixture. The release signer also
requires a private Vault route and the reviewed AWS-auth role before it can
perform a Transit operation.

Do not enable the current GHCR image reference in the private-only CodeBuild
project. The signer security group permits HTTPS only inside the VPC CIDR and
the baseline has no NAT route, while GHCR is an external registry. AWS documents
that VPC CodeBuild builds need a NAT path for public endpoints, and recommends
an in-region Amazon ECR image for custom-image pull failures. The safe next
design is to mirror the reviewed signer image to a private ECR repository in
`ap-northeast-2`, pin its ECR digest, and keep the existing ECR API/ECR DKR and
S3 private endpoints. The live review must additionally confirm the required
private endpoints for the build's actual calls, including STS for Vault AWS
authentication and CloudWatch Logs for encrypted build logs.

No Terraform apply, AWS, Vault, or EKS action occurred during this review.

References: [AWS CodeBuild VPC networking](https://docs.aws.amazon.com/codebuild/latest/userguide/vpc-support.html) and [AWS CodeBuild troubleshooting for custom images](https://docs.aws.amazon.com/codebuild/latest/userguide/troubleshooting.html).
