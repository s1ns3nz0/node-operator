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
