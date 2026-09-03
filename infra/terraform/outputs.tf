output "cluster_name" {
  description = "Private EKS cluster name; this does not expose an endpoint or credential."
  value       = aws_eks_cluster.private.name
}

output "private_subnet_ids" {
  description = "Private worker subnet identifiers."
  value       = aws_subnet.private[*].id
}

output "audit_bucket_name" {
  description = "Private audit bucket name."
  value       = aws_s3_bucket.audit.id
}

output "vault_unseal_key_arn" {
  description = "KMS key ARN for Vault auto-unseal configuration; no secret material is exposed."
  value       = aws_kms_key.vault.arn
}

output "vault_role_arn" {
  description = "IAM role ARN for the Vault Pod Identity association."
  value       = aws_iam_role.vault.arn
}

output "release_artifact_bucket_arn" {
  description = "Dedicated release artifact bucket ARN when signer is enabled."
  value       = var.enable_release_signer ? aws_s3_bucket.release_artifacts[0].arn : null
}

output "release_artifact_kms_key_arn" {
  description = "Dedicated KMS key ARN for release artifacts when signer is enabled."
  value       = var.enable_release_signer ? aws_kms_key.release_artifacts[0].arn : null
}

output "release_artifact_replica_bucket_arn" {
  description = "Tokyo disaster-recovery release artifact bucket ARN when signer is enabled."
  value       = var.enable_release_signer ? aws_s3_bucket.release_artifacts_replica[0].arn : null
}

output "release_signer_ecr_repository_arn" {
  description = "Private signer-image ECR repository ARN when the ECR mirror foundation is enabled."
  value       = var.enable_release_signer_ecr_mirror ? aws_ecr_repository.release_signer[0].arn : null
}

output "release_signer_ecr_repository_url" {
  description = "Private signer-image ECR repository URL when the ECR mirror foundation is enabled; image digests are non-secret."
  value       = var.enable_release_signer_ecr_mirror ? aws_ecr_repository.release_signer[0].repository_url : null
}
