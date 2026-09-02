# Private EKS Terraform baseline

This directory is a contract-free, offline-only Terraform baseline for the
node-operator infrastructure. It creates no state backend and invokes no
remote Terraform modules. The configuration deliberately defines no Internet
gateway, NAT gateway, public subnet, public IP assignment, or public EKS API
endpoint.

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
