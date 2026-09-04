# Vault Raft bootstrap remediation

1. Record the live diagnosis: vault-1 and vault-2 had uninitialized empty Raft stores and were manually joined with the chart TLS material.
2. Encode the same private TLS join route as a chart retry_join configuration.
3. Validate the values contract and toolchain image input tracking.
4. Merge under delegated authority and publish a reviewed bootstrap toolchain image before a future Helm reconciliation.
