# Private Vault delivery path

1. Inventory the private cluster, ECR, chart, runtime-image, and TLS-secret-existence prerequisites without reading secret data.
2. Add a dedicated least-privilege Terraform delivery executor and private ECR destination, with no public egress or cluster-admin access.
3. Add a pinned mirror and dry-run contract that fails closed until every required Vault artifact is available privately.
4. Review Terraform plan before any AWS apply or OCI mirroring; the sealed Helm deployment remains a subsequent task step.
5. Record non-sensitive evidence and obtain an independent clean-room debrief.
