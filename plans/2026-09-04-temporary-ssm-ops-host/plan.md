# Temporary private SSM operations host

1. Reuse the existing private VPC endpoint architecture and create one no-public-IP EC2 instance in an approved private subnet.
2. Attach only the SSM managed-instance permissions required for Session Manager; create no SSH key and no inbound rule.
3. Add a one-time UTC schedule equivalent to 22:00 KST on 2026-09-04 that terminates the instance.
4. Review a refresh-backed saved plan for only the host, its private security/IAM profile, and stop scheduler resources before apply.
5. Verify private placement, zero inbound security-group rules, SSM management availability, and the exact stop schedule without opening a Kubernetes session.

The host is a TCP tunnel target only. Kubernetes, Vault, Helm, CodeBuild, and Secrets remain out of scope.
