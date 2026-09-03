# Private Vault Helm deployment

1. Confirm the private EKS, Pod Identity, KMS, and externally managed TLS-secret prerequisites without reading secret data.
2. Render the reviewed Vault values and fail closed if a required external prerequisite is absent.
3. Apply only the internal Vault Helm release, then verify three replicas, internal-only services, and sealed health.
4. Record non-sensitive evidence and obtain an independent debrief.

Vault initialization and unseal remain a separately authorized operator procedure.
