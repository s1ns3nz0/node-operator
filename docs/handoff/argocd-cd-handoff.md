# Argo CD CD handoff

Terraform apply must stop after infrastructure readiness: VPC, private EKS,
managed nodes, required addons, IAM, KMS, audit resources, and VPC endpoints.

After an approved apply, the CD operator performs:

1. Verify `kubectl` access to the private cluster from an approved runner.
2. Install a pinned Argo CD release using the approved manifest source.
3. Register an Argo CD `Application` whose `repoURL`, `targetRevision`,
   `path`, destination cluster, and namespace are reviewed before submission.
4. Wait for `Synced` and `Healthy`; record only non-sensitive status, commit SHA,
   and timestamps as evidence.
5. On failure, stop promotion and use Argo CD rollback/reconcile. Do not patch
   workload resources manually as a substitute for Git changes.

Repository credentials, tokens, cluster-admin kubeconfigs, and production
destinations are injected by the approved runner and must never be committed.
