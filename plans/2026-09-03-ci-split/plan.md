# CI split

1. Separate fast quality checks, security scanners, Terraform checks, and policy tests.
2. Make a final evidence gate consume the independent results and remain the only merge-blocking policy decision.
3. Keep AWS apply and Argo CD sync outside PR CI and require an explicit environment approval.
4. Validate harness structure and workflow syntax before handoff.
