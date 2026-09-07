# Argo client bootstrap

1. Reconcile only the short-lived ECR repository credential inside `argocd`.
2. Apply the reviewed OCI Application definition during the existing bootstrap.
3. Validate source and Terraform contracts before merge; use the existing temporary bootstrap-admin ceremony only when executing the already-approved bootstrap.
