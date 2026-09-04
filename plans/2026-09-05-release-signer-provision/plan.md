# Private release signer provision

1. Validate the signer-only Terraform plan has no deletes.
2. Provision the private artifact, IAM, KMS, logging, networking, and CodeBuild resources.
3. Correct and verify the minimum CodeBuild VPC attachment permission.
4. Configure and test Vault AWS auth without recording token material.
