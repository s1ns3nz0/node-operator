## Summary

Adds a **read-only, manual main-only verification path** for the three existing frozen Vault server/Agent/Injector candidates. No rebuild, image push, signing, Terraform apply, Vault access or live rollout occurs in this PR/workflow.

- Exact committed ECR digest allowlist, offline non-root version probe, fresh SBOM/raw Grype evidence and digest-bound summary.
- Dedicated disabled-by-default OIDC role: immutable owner/repository-ID prefix plus exact `ref:refs/heads/main`; only three runtime repositories can be pulled. No paid environment protection dependency. Other OIDC-enabled main workflows can assume this read-only role; this is not exact-workflow trust.
- Credentials removed from scanner subprocess environments; temporary OIDC, AWS and Docker auth files cleaned. Artifacts contain only non-sensitive runtime/scan output.

## Risk assessment and deployment boundary

Current local scans of all three frozen subjects have C=0/H=0/M=3/U=1. The retained Unknown is GO-2026-5932. Existing exact-package-closure non-applicability evidence is **not** turned into an automatic pass or global exclusion here. Unknown still blocks the hosted scan gate until a separately reviewed applicability path is integrated. Passing this job would still not establish build provenance or authorize deployment.

The workflow did not build these images, so it never fabricates a GitHub/SLSA build attestation. Signing and live HA/KMS/auth/admission gates remain separate. This PR changes no running workload or PVC.

## Validation

- Seven scan unit tests; IAM trust/permission negative tests; seven wrapper/workflow negative mutations: PASS.
- Repository-wide ShellCheck, Terraform fmt/validate with locked AWS provider, workflow YAML parsing, harness check, diff check: PASS.
- Actual Docker version/identity probes on all three frozen candidates: PASS, network disabled and no credentials mounted.
- Fresh local Grype 0.111.0 observations recorded separately from the future hosted pinned 0.118.0 run.
- Independent Terra review approved after credential-boundary and negative-test improvements.

## After merge

Review only the new verifier role/policy Terraform plan, configure its repository variable, and dispatch the workflow. Do not apply incomplete reconciliation inputs or deploy from a failed/incomplete verification.
