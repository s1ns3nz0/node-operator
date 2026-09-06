# Zero-resource release sequence

The release starts without any node-operator cloud resource. Its first phase
uses local Terraform state only to create the encrypted S3 backend and DynamoDB
lock table in `infra/bootstrap-state`. Every later phase must initialize using
the non-secret `backend` output from that root.

The next implementation phase is `foundation-network`: it will own the VPC,
public NAT egress edge, private worker subnets, and the NAT EIP required by
Hoodi peers. The baseline must consume those outputs and must not create a
second VPC or accept an externally supplied NAT ID.

Destroy testing is intentionally deferred. The state backend itself must be
destroyed last from local state only after every dependent root is empty and
its S3 state object is no longer needed.
