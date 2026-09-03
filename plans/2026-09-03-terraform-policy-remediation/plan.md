# Terraform policy remediation

1. Reproduce and classify every current offline Terraform policy finding.
2. Choose configuration changes that preserve the private EKS, encryption, and least-privilege boundaries.
3. Implement the bounded design changes and update policy fixtures only where the policy intent is demonstrably wrong.
4. Run offline Terraform, Checkov, OPA, and harness validation.
5. Obtain independent review, record non-sensitive evidence, and integrate. Remote push requires a separate authorization.
