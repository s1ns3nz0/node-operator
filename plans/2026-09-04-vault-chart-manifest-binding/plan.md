# Vault chart manifest binding

1. Record the reviewed private-ECR manifest digest for chart tag `0.31.0`.
2. Make the chart mirror verify that its post-push ECR digest equals that record.
3. Pass the record into the private bootstrap executor and fail before Helm if
   the ECR tag resolves differently.
4. Scope the executor's read permission to the chart repository and correct
   the Helm OCI reference to the chart repository path.
5. Prove the contract with offline tests; do not apply or execute CodeBuild.
