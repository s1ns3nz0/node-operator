# T-2 AWS preflight clean-room debrief

## Scope and outcome

This task prepared a private EKS Terraform baseline for a later, explicitly
authorized AWS validation. It did not create or change AWS resources, access
secrets, execute `terraform apply`, execute `terraform plan`, or make AWS API
calls.

The completed bundle records the intended cost and support posture: the
Kubernetes version default is `1.35`, and `aws_eks_cluster.private` sets
`upgrade_policy.support_type = "STANDARD"`. Together, these changes avoid an
extended-support enrollment for this baseline; a future operator must still
upgrade before the applicable standard-support window ends.

## Observed implementation

Compared with base commit `3729ede`, the Terraform changes add the following
private service-access design:

- Interface endpoints: `ec2`, `ecr.api`, `ecr.dkr`, `eks-auth`, and `kms`.
- An S3 gateway endpoint associated with the private route table.
- Private DNS for every interface endpoint, placed in both private subnets.
- An endpoint security group that permits only TCP/443 ingress from the
  managed-node security group; the node group depends on the endpoints.
- A private-only EKS API remains the boundary. No NAT gateway, internet
  gateway, public subnet, public route, public IP assignment, or public EKS
  API endpoint is introduced.

Endpoint policies are not implemented by this change. They are future
hardening work to define alongside each approved service's access and policy
requirements, not a control claimed as present here.

The documentation also supplies an authorized apply/destroy runbook. A later
task must obtain explicit approval for a non-production account and controlled
state workspace; confirm the account, `ap-northeast-2` region, change ticket,
provider mirror, and a reviewed plan with no NAT, internet gateway, public
subnet, or public EKS endpoint. It must preserve the plan digest, caller
identity, workspace, and endpoint IDs. Before destroy, dependent workloads and
retained/referencing resources must be removed; then an approved destroy plan
must be run in that same state workspace and removal of EKS resources, endpoint
ENIs, the S3 route-table entry, and associated security groups verified.

## Evidence and review

The supplied check results are:

- `terraform fmt -check -recursive` — passed.
- `terraform validate -no-color` — passed.
- `npm run harness:check` — passed, reporting 8 graphs.
- `git diff --check` — passed.

The task bundle records that an independent review found and corrected the
missing `STANDARD` upgrade policy and incomplete task bundle. The supplied
review conclusion confirms that Kubernetes 1.35 plus the `STANDARD` policy
clears the extended-support blocker and that the completed bundle is complete.

## Residual conditions

This is a preflight, not a deployed environment. Runtime endpoint availability,
DNS behavior, node bootstrap, image pulls, endpoint security enforcement, and
destroy behavior remain to be verified only in the future authorized AWS task.
That task must also assess any conditional endpoints required by approved
workloads, logging, identity, or operations tooling (for example STS,
CloudWatch Logs, or Systems Manager) before relying on them.
