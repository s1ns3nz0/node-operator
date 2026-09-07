# Private CD, DAST, and validator assurance

1. Bind the dedicated CodeBuild identity to a static Kubernetes group and give that group only `get` on Argo `Application` objects in `argocd`.
2. Verify the private GitHub Actions runner reaches EKS and fails closed when the observed Argo revision is not the requested OCI digest.
3. Add reviewed GitOps source for digest promotion and a bounded, disposable DAST target/scanner path; package, sign, scan, and exercise it on the private runner.
4. Collect non-secret operational evidence for UC-1 through UC-5. Do not invent a Vault credential or sign with a keystore.
