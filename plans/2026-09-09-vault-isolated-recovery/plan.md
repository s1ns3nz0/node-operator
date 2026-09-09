# Isolated recovery infrastructure

1. Create a separate Terraform root for a dedicated VPC, private EC2 container host and AWS service endpoints. No live EKS networking or Kubernetes objects are reused.
2. Bind host IAM to one S3 snapshot object/version, transport KMS decryption through S3, required auto-unseal KMS operations, exact ECR repositories and Session Manager channels. No live key policy replacement or grants by the workload.
3. Pin an AWS-owned ECS AL2023 AMI with Docker preinstalled, disable ECS registration, use basic monitoring, encrypted disk and IMDSv2. Do not restore a snapshot or fetch tokens in user-data.
4. Test offline plan/validation and least-privilege negative cases in pinned container tools; independent review before merge/apply.
5. Apply only a reviewed create-only saved plan in a distinct remote backend with verified principals. Verify live isolation and SSM/bootstrap health before any custody-bearing operation.
6. Implement isolated recovery ceremony, verify restored token/audit boundaries and upgrade. Then return to reviewed live standby rollout and singleton client activation.
