# Bootstrap-state reconciliation

This module defaults to a new deployment name and baseline state key:

- bucket: `node-operator-tfstate-<account-id>-apnortheast2`
- key: `node-operator/baseline/terraform.tfstate`

The current account has an older bucket name,
`node-operator-tfstate-106760547719-apne2`, and the existing baseline backend
uses `node-operator/t2/terraform.tfstate`. Reconciliation is an explicit,
reviewed import exercise. It is not a fresh `terraform apply`, and it must not
be automated by CI or release tooling.

## Prepare reviewed inputs

No import, state copy, backend migration, plan approval, or apply is
authorized by this document. For a future separately approved review, create a
fresh private operator directory outside Git, copy the module and its lockfile
there, and run all Terraform commands only against that copy:

```sh
operator_root="$(mktemp -d "${TMPDIR:-/tmp}/node-operator-bootstrap-state.XXXXXX")"
chmod 700 "$operator_root"
cp -R /ABSOLUTE/PATH/TO/REPOSITORY/infra/bootstrap-state "$operator_root/module"
```

Using a permissions-restricted editor in `$operator_root`, create a non-secret
`bootstrap-state.reconciliation.tfvars` file with the exact observed values.
Do not commit the file or any Terraform state, plan, backend configuration, or
`.terraform/` directory.

```hcl
aws_account_id      = "106760547719"
state_bucket_name   = "node-operator-tfstate-106760547719-apne2"
baseline_state_key  = "node-operator/t2/terraform.tfstate"
backend_principal_arns = [
  "arn:aws:iam::106760547719:role/REVIEWED_TERRAFORM_BACKEND_ROLE",
]
```

The allowlist accepts only exact same-account IAM role ARNs. It is empty by
default. The S3 state CMK policy then grants listed roles only `Decrypt`,
`GenerateDataKey`, and `DescribeKey`, with account, S3 service, and state
bucket encryption-context restrictions. For the regional DynamoDB lock table,
it also grants the exact crypto actions only through DynamoDB in the configured
Region and only with the exact lock-table/account encryption context. Backend
roles receive no `CreateGrant` or key-administration permission. The separately
authorized bootstrap updater must already have the permissions DynamoDB needs
to create its service-managed grants when changing the table key. Global tables
and cross-Region DynamoDB use are outside this module's contract.

Changing encryption still requires a reviewed imported-state plan. Verify the
actual backend role can read/write a non-sensitive canary and acquire/release
an isolated lock; repeat its read after DynamoDB's five-minute key cache window.
Never use a real Terraform lock ID as the canary. A successful administrator
request is not proof of backend-role access.

## Import workflow

1. In the private operator directory, place the reviewed tfvars file and
   authenticate as the approved account role. Never put credentials, backend
   configuration, `.terraform/`, `terraform.tfstate*`, or plan files in Git.
2. Confirm identity and the existing resource inventory with read-only AWS
   commands. The six observed existing resources are listed below. Do
   not infer an additional resource ID from a generated Terraform name.

   | Terraform address | Reviewed import ID |
   | --- | --- |
   | `aws_s3_bucket.state` | `node-operator-tfstate-106760547719-apne2` |
   | `aws_s3_bucket_versioning.state` | `node-operator-tfstate-106760547719-apne2` |
   | `aws_s3_bucket_server_side_encryption_configuration.state` | `node-operator-tfstate-106760547719-apne2` |
   | `aws_s3_bucket_public_access_block.state` | `node-operator-tfstate-106760547719-apne2` |
   | `aws_s3_bucket_policy.state` | `node-operator-tfstate-106760547719-apne2` |
   | `aws_dynamodb_table.lock` | `node-operator-terraform-lock` |

   The current state bucket uses SSE-S3. No existing state CMK was observed,
   so `aws_kms_key.state` is not an import target.
   The observed state bucket policy denies insecure transport. Preserve that
   denial and add the scoped SSE-C write denial; never overwrite other policy
   statements without reviewing a fresh inventory. Also verify the bucket's
   native `BlockedEncryptionTypes` remains `SSE-C` before and after changing
   default encryption. Provider 5.x does not represent that native setting;
   a zero-drift Terraform plan alone cannot prove it was preserved.
3. Initialise without a backend and validate the reviewed configuration:

   ```sh
   terraform -chdir="$operator_root/module" init -backend=false -lockfile=readonly
   terraform -chdir="$operator_root/module" validate
   ```

4. Only if a later approval explicitly authorizes import, use explicit
   Terraform state commands for exactly the reviewed address/ID pairs:

   ```sh
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_s3_bucket.state node-operator-tfstate-106760547719-apne2
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_s3_bucket_versioning.state node-operator-tfstate-106760547719-apne2
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_s3_bucket_server_side_encryption_configuration.state node-operator-tfstate-106760547719-apne2
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_s3_bucket_public_access_block.state node-operator-tfstate-106760547719-apne2
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_s3_bucket_policy.state node-operator-tfstate-106760547719-apne2
   terraform -chdir="$operator_root/module" import -var-file="$operator_root/bootstrap-state.reconciliation.tfvars" aws_dynamodb_table.lock node-operator-terraform-lock
   ```

   Keep the resulting local state private. Do not import any remaining module
   resource without a new observed inventory and approval.
5. Run a refresh-only plan and a normal plan with the same private inputs.
   A reviewer must verify that there are no replacements or deletes before any
   change is considered. New CMK and unobserved child-resource configuration
   creation is separate from importing these six resources, and requires a
   saved, reviewed imported-state plan. `prevent_destroy` protects the state
   bucket and lock table, but it is not an approval to alter their live
   settings.
6. Only after that review, configure the remote backend explicitly through a
   private backend configuration file or the approved `terraform init
   -backend-config=...` invocation from `$operator_root/module`. Do not copy
   state to a backend or apply this module as part of this workflow without
   separate authorization.
