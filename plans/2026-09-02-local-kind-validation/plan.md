# Local Kind validation

1. Inspect workload assumptions and create a disposable Kind cluster.
2. Add a local-only overlay that neutralizes AWS storage and resource-size assumptions.
3. Apply server-valid manifests and check Pod Security, ServiceAccounts, RBAC, and NetworkPolicy objects.
4. Remove the cluster, record evidence, and obtain independent review/debrief.
