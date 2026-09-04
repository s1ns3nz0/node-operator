# Clean-room debrief: Vault bootstrap live prepare plan

## Observed evidence

- The task was explicitly plan-only: runner enabled, cluster-admin disabled, and no apply or deployment action permitted.
- Read-only subnet and ECR artifact-digest inputs succeeded.
- The refresh-backed Terraform plan stopped at `kms:DescribeKey` while refreshing existing managed KMS keys. It produced no plan artifact and changed no resource.
- A no-refresh diagnostic proposed ten Vault prepare creates and eight Argo CD bootstrap deletes. It was rejected because the task branch lacks the configuration that owns those state resources.

## Inference and conclusion

Neither result is safe for apply: the refresh is incomplete and the no-refresh result carries destructive configuration/state drift. The observed deletes do not authorize deletion.

## Safe retry prerequisite

Use a read-only Terraform planning principal with `kms:DescribeKey` on every state-managed KMS key, from a task branch aligned with the deployed Argo CD bootstrap configuration. Then generate a new refresh-backed runner=true/cluster-admin=false plan and reject it if it contains Argo CD deletes, any cluster-admin association, or public-network resources.
