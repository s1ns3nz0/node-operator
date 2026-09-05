# Plan

1. Configure the private Vault AWS-auth role to use regional STS.
2. Deliver only the Vault public CA to CodeBuild through Secrets Manager.
3. Require the CA, regional STS signing, and port 8200 in the durable signer contract.
4. Verify an AWS-authenticated Transit sign and verify operation without TLS bypass.
