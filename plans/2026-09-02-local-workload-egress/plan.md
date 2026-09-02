# Local workload-specific egress validation

1. Create labelled local-only gateway fixtures and restricted probes.
2. Apply the shared base and both workload policy sets to the Cilium cluster.
3. Verify allowed and denied TCP/UDP paths for Prysm and Nethermind.
4. Delete fixtures, record evidence, and obtain a clean-room debrief.
