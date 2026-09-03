# Clean-room debrief: T-2 AWS preflight

## Scope and authorization

The task prepared a cost-aware private EKS Terraform baseline and the bounded
AWS state backend/apply identity needed for a later real-AWS validation. The
authorized AWS mutations were limited to the encrypted/versioned S3 state
bucket, DynamoDB lock table, `NodeOperatorTerraformApply` role and scoped
policy, caller assume-role permission, and the local `node-operator-t2`
profile. EKS/VPC application, deployment, secrets, NAT, and production access
were out of scope.

## Implemented result

The baseline pins Kubernetes 1.35 and sets EKS `upgrade_policy.support_type` to
`STANDARD`, avoiding extended-support enrollment. The network remains private:
private subnets have no public IP assignment, internet gateway, NAT gateway, or
public EKS API endpoint. Private node bootstrap dependencies are represented by
interface endpoints for `ec2`, `ecr.api`, `ecr.dkr`, `eks-auth`, and `kms`, plus
an S3 gateway endpoint. Endpoint security-group ingress is restricted to
managed nodes on TCP/443, and the node group explicitly depends on endpoint
creation.

Commit `4116069` adds the approved S3 backend configuration at
`node-operator-tfstate-106760547719-apne2/node-operator/t2/terraform.tfstate`
in `ap-northeast-2`, with DynamoDB locking through
`node-operator-terraform-lock`, and documents the backend in the Terraform
README. It also adds the reviewed apply-policy bundle. The policy is scoped to
the named state bucket, approved audit-bucket patterns, the named lock table,
and `sts:GetCallerIdentity`.

## Evidence and checks

The recorded evidence reports the backend bucket as versioned, AES256-encrypted,
public-access-blocked, and TLS-only; the lock table is PAY_PER_REQUEST and
`ACTIVE`. It reports that `NodeOperatorTerraformApply` has external-ID trust for
`jsyang`, that the scoped policy is attached, and that the
`node-operator-t2` profile successfully assumes the role.

The recorded static checks passed: recursive Terraform formatting check,
`terraform validate -no-color`, `npm run harness:check`, and `git diff --check`.
No Terraform provider download, infrastructure plan, or EKS/VPC apply occurred.

## Review status and handoff

An independent review completed with fixes, including correction of the
STANDARD support policy and task bundle. The evidence explicitly calls for a
fresh review after backend/role integration. The next authorized build task
must use the controlled provider mirror and reviewed plan, record plan digest,
caller identity, workspace, and endpoint IDs, and obtain exact-plan approval
before apply. Teardown must be performed from the same controlled state
workspace using an approved destroy plan and post-destroy verification.

This debrief is a clean-room summary of the supplied task bundle, Terraform
changes, commit `4116069`, validation results, and AWS backend/role evidence.
