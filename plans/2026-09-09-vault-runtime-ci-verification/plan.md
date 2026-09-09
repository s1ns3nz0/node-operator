# Frozen Vault runtime CI verification

1. Confirm frozen candidates and existing source/runtime evidence.
2. Add a disabled-by-default, exact-main-subject OIDC role that can only pull the three runtime repositories; never reuse a publisher role or depend on paid environment protections.
3. Add a manual main-only workflow to pull exact digests, collect fresh SBOM/raw scan/runtime identity and retain non-sensitive evidence. No build or signing claim.
4. Test positive and negative contracts, independently review, then open one scoped PR.
5. After merge, review the narrow Terraform plan and repository variable configuration separately, execute verification, and resolve release eligibility before any live rollout.

Historical local package-closure assessments are not a CI build attestation. Unknown findings remain visible and block release eligibility. No generalized Vault exception is introduced.
