# Access-log replication

This configuration is a proposal only. It adds live, one-way S3 cross-region
replication from the Seoul access-log buckets to the existing Tokyo DR
access-log buckets:

| Source | Included object prefixes | Destination |
| --- | --- | --- |
| `audit_access_logs` | `audit/`, `validator-audit/`, `vault-snapshot/` | `audit_replica_access_logs` |
| `release_artifacts_access_logs` (when `enable_release_signer=true`) | `release-artifacts/` | `release_artifacts_replica_access_logs` |

The proposed Terraform addresses are
`aws_s3_bucket_replication_configuration.audit_access_logs` and
`aws_s3_bucket_replication_configuration.release_artifacts_access_logs[0]`,
with their corresponding dedicated `aws_iam_role` and `aws_iam_role_policy`
resources in `access-log-replication.tf`.

S3 replication preserves object keys. The destination writes therefore use
those same prefixes; they do not write to `audit-replica/` or
`release-artifacts-replica/`. Those latter prefixes are reserved for the Tokyo
source buckets' own server-access-log delivery and remain non-colliding.

Each configuration has a dedicated role with the documented `s3.amazonaws.com`
service trust. Its separate identity policy limits source reads and destination
writes to the listed bucket and prefix ARNs; the trust policy does not rely on
`aws:SourceArn` or `aws:SourceAccount`, because the S3 replication
AssumeRole request does not document those context keys. It does not grant
deletion, ownership override, KMS, batch replication, replica-modification
synchronization, or reciprocal-replication permissions. Both destination
buckets keep their existing AES256 (SSE-S3) default encryption; the replication
rules deliberately do not set a destination KMS encryption configuration.

S3 live replication applies to objects created after its configuration is
added; it is not a backfill mechanism. S3 also does not automatically
re-replicate replicas, so the absence of a reciprocal rule is intentional.
See [What does Amazon S3 replicate?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-what-is-isnot-replicated.html)
and [Setting up permissions for live replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/setting-repl-config-perm-overview.html).

## Rollout constraints

No cloud change is authorized by this proposal. Before a future, separately
approved activation, create and review a saved Terraform plan. It must contain
only the two access-log replication configurations and their dedicated IAM
roles and inline policies; it must show no replacements or deletions. Confirm
both source and destination versioning resources are enabled, and confirm the
release configuration is present only when `enable_release_signer=true`.

After activation, write fresh source objects and verify their replication
status and same-key destination presence. Do not use S3 Batch Replication or
another backfill process without a separate approval.

The existing Seoul-to-Tokyo DR pattern incurs inter-region replication transfer,
destination S3 request, and destination storage/lifecycle charges. Estimate
the observed access-log volume and retention before activation; lifecycle
policies retain the current 90-day Standard-IA and 365-day Glacier transition
pattern, with 365-day expiry for these log buckets.
