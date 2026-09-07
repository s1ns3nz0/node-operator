# Vault prepare live-plan retry

1. Confirm the existing scoped Terraform role and state-aligned remediation branch.
2. Re-verify the private runtime, toolchain, and chart digests.
3. Generate a refresh-backed plan with only the Vault runner enabled.
4. Reject the plan if it deletes or changes Argo CD bootstrap resources, contains a Vault cluster-admin association, creates public-network resources, or includes any non-prepare mutation.
5. Record non-sensitive evidence and obtain a clean-room review. This task never applies the plan.
