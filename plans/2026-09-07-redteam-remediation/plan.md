# Red-team remediation

1. Pin every GitHub Action in build/publish workflows and add a regression check.
2. Bind the release workflow to a fail-closed, digest-bound release-evidence decision.
3. Add GitOps OCI artifact SBOM, scan, provenance, signature, and retained evidence contracts.
4. Add private GitOps CD verification that checks Argo revision/sync/health before the bounded DAST contract.
5. Add governance checks for required review, signed commits, and required checks; state service-plan limitations explicitly.
6. Validate source contracts without publishing or contacting private workloads.
