# DevSecOps full remediation plan

1. Inventory Node Operator and GitOps workflow trust boundaries, GitHub protections, cloud roles, and currently deployed chart state.
2. Correct repository-level protections and enable available GitHub security features with evidence captured outside of CI artifacts.
3. Add static workflow validation and source contracts that reject unpinned actions, unsafe trigger data, excessive permissions, and unsafe DAST execution.
4. Extend the private CD runner only through its existing namespaced RBAC to create a disposable, loopback-only ZAP passive-scan Job from the approved private digest; collect a scrubbed summary and delete the Job.
5. Publish and promote the GitOps chart, run actual private-CD plus DAST evidence, then re-run the red-team inventory.
6. Create a disabled-by-default, KMS-encrypted private ECR mirror foundation for the reviewed Web3Signer and PostgreSQL digests. Bind its GitHub OIDC identity to one dedicated environment and prevent arbitrary mirror sources.
7. Run read-only UC readiness/activity checks; perform secret-dependent UC actions only when a human supplies credentials interactively.

The main integration owner is Sol. No fallback was needed.
