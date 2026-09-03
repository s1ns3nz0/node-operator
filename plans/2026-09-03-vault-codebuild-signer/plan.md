# Private CodeBuild + Vault Transit signer

1. Define trust boundaries and OIDC/IAM contracts.
2. Run signing inside private CodeBuild; Vault Transit never exports keys.
3. Add release verification gate before publication/deployment.
4. Validate locally without creating AWS resources.
