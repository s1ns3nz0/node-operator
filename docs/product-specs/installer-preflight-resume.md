# Installer preflight and resume

Status: approved. Authority: [accepted decision](../decisions/2026-09-13-installer-preflight-resume.md).

## Required behavior

1. Confirm the selected AWS account, Region, deployment identity, and release inputs.
2. Verify required tooling and approved image/chart sources before network creation. Unknown access failures are errors, not evidence of absence.
3. Use an existing, correctly bound deployment state or create a new backend for a new deployment. Never adopt another project's resources by name alone.
4. Prepare only required ECR prerequisites in that same state, copy approved artifacts, and verify their destination digests before VPC/EKS creation. Do not build substitutions or invent digests.
5. On interruption, preserve state and retry the same deployment. Refresh state and regenerate plans rather than trusting partial outputs or replaying stale plans. Reject destructive ordinary retry plans.
6. Keep SSM as a separate infrastructure phase. Preserve interactive Vault ceremonies and validator activation gates; do not automatically repeat initialization, deposits, or signing activation.

## Acceptance

Offline executable tests must demonstrate source and destination failures blocking cluster creation; owned new/existing destinations; same-state recovery from a partial Terraform apply; nonzero failure propagation; and rejection of mismatched or unsafe work directories. Offline checks do not establish successful AWS deployment.

## Implementation boundaries

Deployment identity is the confirmed AWS account, Region, and deployment name from the generated bootstrap, foundation, and baseline JSON configurations. Checkpoints must bind these inputs; a mismatched or unknown nonempty directory is not adopted. Backend bucket and table names come from those configurations, never from an unchecked output file. An ordinary retry rejects any Terraform action containing `delete`, including replacement, and regenerates its plan with refresh enabled.

Before VPC/EKS, only local preparation, deployment-owned state backend resources and ECR prerequisites may be created. ECR prerequisites include encryption keys and their required administration role where the existing module requires them; they must remain in the same baseline state as the later full apply. A partial targeted plan is not evidence of full infrastructure completion. SSM retains the existing separate `ops-access` state and explicit phase.

Artifact approval remains in the bundled platform, GitOps and validator approval records. Operator-supplied fence/client-chart references require exact immutable source bindings. A conflict between an approved record and an effective workload digest is unresolved, not permission to choose a replacement. Missing-object responses may enable creation; authorization failures, malformed responses and ambiguous discovery stop the affected phase.

For Vault, the [accepted artifact authority decision](../decisions/2026-09-13-vault-artifact-authority.md) requires removal of ad hoc digest substitutions. Rendering and mirroring must consume the same approved records for server, agent, injector and audit relay; missing records must fail rather than select an unapproved fallback.

Interactive entrypoint checkpoint selection and source-to-consumer mapping are implementation work still in progress. Until they are tested and integrated, the standalone `zero apply` retry changes do not imply the single-entry installer supports end-to-end resume.
