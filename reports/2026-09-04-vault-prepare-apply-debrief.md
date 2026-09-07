# Clean-room debrief: Vault prepare apply

## Conclusion

The retained task evidence supports the recorded prepare-only outcome: all ten intended resources were created across the initial partial apply and the successful two-resource resume. The Vault EKS access entry is recorded as `STANDARD` with zero associated access policies, and the Vault CodeBuild project exists with zero builds. No blocking inconsistency was found in the task bundle or current Terraform definitions.

## Checked evidence

- The prior refresh-backed allowlist names exactly ten creates and one local IAM policy-document read. The apply bundle records the eight resources created before the initial stop, then a regenerated saved plan with only `aws_eks_access_entry.vault_bootstrap[0]` and `aws_codebuild_project.vault_bootstrap[0]` (zero changes and deletes), followed by a successful apply.
- The initial stop is attributed to exactly two absent permissions: `eks:CreateAccessEntry` and `codebuild:CreateProject`. The approved remediation is recorded as adding only those actions plus `iam:PassRole` restricted to CodeBuild.
- `infra/terraform/vault-bootstrap.tf` defines the entry as `STANDARD`; its only cluster-admin association has a count requiring `enable_vault_bootstrap_cluster_admin=true`. The reviewed inputs set that value false. The final readback records zero associated access policies.
- The same file defines a private, `NO_SOURCE` CodeBuild project; the final readback records the project and a build count of zero. The ten-create allowlist and resumed two-create plan contain no public-network, deployment, or cluster-admin-association action. The task evidence separately records that no CodeBuild run, Helm, kubectl, Vault, secret access, merge, or publication occurred.
- Read-only local checks passed: task JSON parses with `jq` and `git diff --check` is clean.

## Evidence gaps

- The bundle retains non-sensitive summaries only, not the Terraform apply diagnostics or AWS CLI/readback outputs. It therefore supports, but cannot independently prove from primary output, that the initial failure was *solely* the two stated missing permissions, that each final resource exists, the access-policy count is zero, or the CodeBuild build count is zero.
- No CloudTrail, CodeBuild audit/history export, EKS audit data, or equivalent independent activity record is retained. The absence of deployment, cluster-admin association, and public-network change is supported by the gated plans and task attestation, but not independently demonstrated by a separate audit artifact.

This review does not authorize CodeBuild execution, Helm/kubectl/Vault use, secret access, cluster-admin association, or any further Terraform apply.
