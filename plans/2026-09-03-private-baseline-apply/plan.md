# Approved private baseline apply

1. Remove mixed inline/standalone ownership of node ingress and declare the node self-ingress as a standalone rule.
2. Read and validate the existing self-rule ID, then import only that rule into the approved backend state.
3. Generate a fresh recovery plan and apply only if it has no update/destroy and retains the approved baseline-only scope.
4. Verify state count and read-only, non-sensitive resource invariants.
5. Record evidence and obtain a clean-room debrief; do not progress to ECR, signer, Vault, or workloads.
