# Private EKS Terraform baseline

This directory is a contract-free Terraform baseline for the node-operator
infrastructure. State uses the approved encrypted S3 backend with DynamoDB
locking, and the configuration invokes no remote Terraform modules. It deliberately defines no Internet
gateway, NAT gateway, public subnet, public IP assignment, or public EKS API
endpoint.

## Private AWS service access

The baseline has no NAT gateway or public route. It therefore creates an S3
gateway endpoint on the private route table and interface endpoints, with
private DNS enabled in both private subnets, for `eks-auth`, `ec2`, `ecr.api`,
`ecr.dkr`, and `kms`. The endpoint security group accepts only
TCP/443 ingress from the managed-node security group. It has no broad CIDR or
public ingress rule.

These endpoints are the must-have baseline for private node bootstrap and
image pulls. They intentionally exclude the EKS management API endpoint
(needed only for management callers inside the VPC) and conditional endpoints such as
CloudWatch Logs, STS, Secrets Manager, SSM, EC2 Messages, SSM Messages, EFS,
and ELB. Add a conditional endpoint only when the corresponding workload,
add-on, logging destination, identity flow, or operations tooling has been
approved and its endpoint security and policy requirements are specified.

`aws_eks_node_group.private` explicitly depends on these endpoints, preventing
managed-node bootstrap from racing their creation. The EKS Kubernetes API is
already private-only through EKS control-plane ENIs; it is not modelled as an
`aws_vpc_endpoint`.

## Offline validation

Use only the repository's checksum-verified provider mirror and committed
provider lock file when an authorized build task supplies them. The PR evidence
collector configures Terraform with a filesystem mirror, `-backend=false`,
`-get=false`, and `-lockfile=readonly`; it must not fall back to direct
downloads.

This task does **not** run `terraform init`, `plan`, or `apply`. The provider
mirror currently has no AWS provider binary and no `.terraform.lock.hcl` is
committed, so full `terraform validate` is intentionally deferred until the
authorized build task provisions both through the controlled mirror process.

`fixtures/offline-baseline.tfvars` and `terraform.tfvars.example` contain a
synthetic, non-secret 12-digit account ID solely to make variable validation
reproducible. They are not deployment inputs.

## Authorized AWS apply and destroy runbook

This runbook is bounded to an explicitly approved, non-production account and
the Terraform state workspace created for this baseline. Do not run it from a
developer workstation using ambient credentials.

1. Confirm the approved account, `ap-northeast-2` region, change ticket,
   controlled state backend, provider mirror, and a reviewed plan showing only
   this baseline's resources. Confirm no NAT gateway, internet gateway, public
   subnet, or public EKS endpoint is proposed.
2. In the controlled runner, initialize only from the approved provider mirror,
   create the plan with the approved non-secret tfvars, and have the designated
   reviewer approve the exact plan artifact before apply. Record the plan
   digest, caller identity, state workspace, and endpoint IDs in change
   evidence.
3. After apply, verify the EKS API is private-only, every interface endpoint is
   available with private DNS in both private subnets, the S3 gateway endpoint
   is associated with the private route table, and endpoint ingress is limited
   to node-security-group TCP/443. Verify no NAT or internet gateway exists.
4. To destroy, first stop dependent workloads and remove any resources that
   retain or reference the cluster. In the same controlled state workspace,
   review and approve a destroy plan, execute it, then verify the endpoint
   ENIs, EKS resources, route-table endpoint entry, and associated security
   groups have been removed. Retain the reviewed plan and verification evidence.
