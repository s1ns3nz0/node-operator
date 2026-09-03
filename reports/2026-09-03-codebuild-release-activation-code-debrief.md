# Clean-room debrief: CodeBuild release activation code

**Reviewer:** Terra clean-room reviewer  
**Reviewed commit:** `726ddcee34cf333fc0877470763f7acba9d53c47`  
**Review boundary:** the completed task bundle and the five implementation
files named in its task contract. No cloud, AWS, Vault, deployment, publishing,
or secret access was performed.

## Observed evidence

- The task contract classifies this as non-trivial and permits repository
  mutation only. It explicitly prohibits Terraform apply, image publication,
  S3 writes, CodeBuild starts, Vault/AWS access, deployment, merge, and secret
  changes. Its model-fallback record is empty.
- The reviewed commit changes only `.github/workflows/release.yml`,
  `infra/terraform/vault-signer.tf`,
  `scripts/ci/test-codebuild-release-activation.sh`,
  `docs/gitops/codebuild-signing-input-contract.md`, and `package.json`.
- The workflow constructs a SHA-named ZIP containing the bundle, checksum,
  provenance, and archive-local buildspec; uploads it with `If-None-Match: *`;
  then supplies the matching provenance-derived revision and source override to
  CodeBuild. It consumes `release-verification.json` through the existing
  release-signature verifier instead of raw Transit response files.
- Terraform keeps signer resources conditional on `enable_release_signer`,
  defaults the signer image to empty, requires a lowercase digest-pinned GHCR
  image and explicit subnet IDs when enabled, sets a deliberately unusable
  default source location, and defines encrypted build-ID-namespaced ZIP
  output under `release-signer-output`.
- The new targeted test asserts the source/output fields, the disabled and
  digest-pinned image guard, immutable upload semantics, verification gate,
  and absence of legacy raw-signature or static-credential patterns.
- Validation results supplied for the completed task are recorded as passed:
  `npm run test:codebuild-release-activation`,
  `npm run test:codebuild-signing-input-contract`,
  `npm run test:vault-release-verification-gate`, `npm run harness:check`,
  `git diff --check`, and
  `scripts/ci/validate-terraform-offline.sh infra/terraform <temp-output>`.
- This reviewer additionally ran `git show --check 726ddce`; it completed with
  no whitespace errors.

## Inference and remaining boundary

The static diff and supplied offline checks support the inference that the
repository code aligns the reviewed immutable input and verification-output
contract while preserving disabled-by-default infrastructure behavior. They do
not establish runtime conformance: no digest-pinned signer image availability,
private CodeBuild networking, Vault route or dynamic identity, deployed IAM
permissions, Terraform plan/apply result, S3 object behavior, or CodeBuild
execution was observed.

External rollout remains unauthorised by the original task contract. A later,
separately approved activation must review the published image digest, private
runtime prerequisites, OIDC role against the deployed project, and the
Terraform plan before enabling and applying the signer.
