# CI/CD findings remediation plan

1. Publish a trusted `CI Evidence Decision` Check Run against the exact PR head SHA for both scanner success and failure paths; require it in source branch rules only after a real positive and negative proof.
2. Replace worktree-only Gitleaks collection with full-history scanning in the pinned scanner boundary and promote the new immutable scanner image before adoption.
3. Restrict release eligibility to source revisions carrying all required checks and a successful exact-SHA evidence decision; bind tag creation to the protected release path.
4. Extend GitOps acceptance to verify Cosign identity/provenance, SBOM SCA, and read-only DAST against the actual private service endpoints.
5. Reconcile Checkov output against fixed resources and explicitly bounded exception records.
6. Run independent review, live feature checks, and a clean-room debrief; update the red-team report only from observed evidence.

Sol owns integration and security decisions. Terra owns isolated GitOps implementation and independent review. Root owns live configuration and Checkov disposition. No fallback has occurred.
