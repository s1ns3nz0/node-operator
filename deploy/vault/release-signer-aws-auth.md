# Vault AWS Auth role

Apply from the Vault administration boundary after the Terraform-managed
CodeBuild role exists:

```sh
vault write auth/aws/role/release-signer \
  auth_type=iam \
  bound_iam_principal_arns="arn:aws:iam::<ACCOUNT_ID>:role/node-operator-baseline-release-signer" \
  policies=release-signer \
  ttl=5m max_ttl=10m
```

The role receives only the `release-signer` Transit policy. No static Vault
token is stored in GitHub, CodeBuild, Terraform state, or artifacts.
