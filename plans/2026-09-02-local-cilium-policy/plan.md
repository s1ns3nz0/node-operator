# Local Cilium policy validation

1. Confirm the Kind cluster and obtain the official Cilium chart details.
2. Install Cilium only in the named local cluster.
3. Use disposable probe Pods to verify default-deny, bounded DNS, and explicit egress behavior.
4. Delete probes, record evidence, and obtain a clean-room debrief.
