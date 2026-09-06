# Private Hoodi redeployment and validator-boundary plan

1. Establish one safe infrastructure execution basis: a full state-aligned
   Terraform plan with no unrelated changes, or an explicitly approved
   SSM-only recovery plan that creates no unrelated cloud resource changes.
2. Create the reviewed temporary private SSM operations host, then open a
   TLS-verified private EKS tunnel without persisting its identifiers.
3. Re-check private EKS access, Argo Application state, node-pool capacity,
   client StatefulSet presence, and `engine-api-jwt` object metadata without
   fetching Secret data.
4. Stop and report if the external custody or immutable GitOps activation
   prerequisite is absent; do not substitute a local Secret or bypass.
5. If every prerequisite is observed, run the reviewed Hoodi session start,
   capture only non-sensitive readiness and connectivity metadata, and then
   run the reviewed stop operation.
6. Verify UC-2 through UC-5 only as contract boundaries: no real validator
   keys, withdrawal credentials, remote signer, or signing duties are created.
7. Remove the temporary host through the same approved Terraform input path.
8. Record redacted evidence, run structural/script checks, and obtain a fresh
   clean-room debrief before declaring the task complete.
