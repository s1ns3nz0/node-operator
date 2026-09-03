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
