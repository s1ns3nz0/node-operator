# Private GitOps foundation

1. Define ECR OCI repositories, immutable artifact contract, and Pod Identity/runner permissions.
2. Add only required private AWS endpoints and a VPC-internal execution path.
3. Validate the disabled-by-default Terraform plan before any live apply.
4. Publish only reviewed deployment artifacts after separate digest review.
