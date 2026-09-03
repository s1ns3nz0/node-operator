# ECR signer mirror and connectivity contract

1. Replace the private CodeBuild runtime image contract with an in-region ECR digest.
2. Declare the minimal STS and CloudWatch Logs private endpoints and endpoint ingress path for the signer.
3. Add a GitHub OIDC ECR mirror contract limited to the signer repository; keep publication disabled pending a separate authorization.
4. Extend offline fixtures and contract tests, then record evidence and independent review.

No cloud, registry, Terraform apply, or secret operation is part of this task.
