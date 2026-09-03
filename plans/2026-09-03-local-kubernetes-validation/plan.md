# Local Kubernetes validation

1. Compare the historical Kind and Cilium worktrees to current main.
2. Transplant only the local overlay, probe, scripts, and task evidence.
3. Run static rendering, then an ephemeral Kind/Cilium validation with zero client replicas.
4. Delete validation probes, preserve pre-existing named clusters, record non-sensitive evidence, obtain independent review, and integrate.
