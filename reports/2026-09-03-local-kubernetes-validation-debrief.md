# Clean-room debrief: local Kubernetes validation

Task: `2026-09-03-local-kubernetes-validation`
Reviewer: Terra clean-room review
Scope reviewed: completed task bundle, current local Kind/Cilium artifacts and
scripts, and the stated check outcomes. No cluster, cloud, remote, or mutation
operation was performed by this reviewer.

## Observed evidence

- The task contract authorizes local repository and ephemeral local-cluster
  mutation only. Its acceptance criteria require zero-replica StatefulSets,
  server-side admission and RBAC checks, Cilium allow/deny dataplane probes,
  and deletion of validation probes while preserving pre-existing named
  clusters unless the user requests deletion.
- The task graph records LK1--LK3 as completed and this clean-room debrief
  (LK4) as the final dependent activity.
- `deploy/local-kind/kustomization.yaml` composes the local resources and
  applies JSON patches setting `prysm-beacon` and `nethermind-execution` to
  `spec.replicas: 0`. The overlay-render test also asserts those values and the
  two digest-pinned client images.
- `scripts/ci/test-local-kind-cluster.sh` targets only
  `kind-node-operator-local`; it performs server-side dry-run admission, apply,
  zero-replica reads, and RBAC checks that `node-workload` can `get` but cannot
  `list` ConfigMaps in `node-operator`.
- `deploy/local-cilium/kind-config.yaml` disables the default CNI, and
  `scripts/ci/test-local-cilium-policy.sh` targets only
  `kind-node-operator-cilium`. The script creates a restricted, digest-pinned
  disposable probe, requires DNS lookup success, and fails if TCP to
  `1.1.1.1:443` succeeds.
- The Cilium script's exit trap deletes `local-policy-probe` with `--wait=true`
  and a 60-second timeout. This is stronger cleanup behavior than a nonwaiting
  delete request, while still tolerating cleanup failure in the trap.
- The supplied `evidence.json` records all four checks as passed:
  `test:local-kind-overlay`, `test:local-kind-cluster`,
  `test:local-cilium-policy`, and `npm run harness:check`. It specifically
  records observed DNS success, denied external TCP, and probe deletion.

## Inference

The reviewed implementation and recorded outcomes are consistent with the task
acceptance boundary: the local Kind overlay can be admitted without starting
either blockchain client; the tested service account has the intended narrow
ConfigMap permission; and Cilium enforced the base DNS-only egress behavior for
the disposable probe. The evidence is also consistent with a non-sensitive,
local-only validation path and does not indicate AWS, EKS, Hoodi, or secret use.

## Limits

- This review verified artifact intent and recorded evidence, not live cluster
  state or raw command logs. It independently reran none of the stated checks.
- The probe demonstrates only local Cilium handling of the base policies. It
  does not prove AWS VPC CNI, EKS admission/runtime behavior, storage,
  KMS/Pod Identity, node placement, multi-node scheduling, or workload-specific
  Prysm/Nethermind egress rules.
- A successful policy probe is not evidence that the full client workloads can
  start, synchronize Hoodi, or operate correctly; the zero-replica design
  intentionally excludes those behaviors.
- Although the task records probe deletion and the script waits for it, this
  clean-room review has no independently observed output proving the eventual
  deletion of the disposable probe. The named Kind clusters pre-existed this
  task and were intentionally preserved.

## Conclusion

No contradiction was found between the completed task bundle, relevant current
diff, and the stated validation results. The recorded evidence supports the
claimed local validation scope, subject to the limits above.
