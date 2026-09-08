# CI/CD optimization plan

1. Inventory source CI/CD phase coverage, permissions, action pins, evidence flow, and blocking dependencies.
2. Verify whether release SBOM generation is followed by vulnerability analysis and a go/no-go threshold.
3. Add a deterministic release SBOM SCA gate using repository-pinned tooling and compact retained evidence.
4. Add meaningful contract tests for fail-closed behavior, exact-SBOM input, workflow ordering, and evidence safety.
5. Run focused checks, harness verification, and an independent review; record the final framework mapping.

Sol is the primary integration and security owner. No model fallback has occurred.
