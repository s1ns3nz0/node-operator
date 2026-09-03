# Clean-room debrief: Vault signer GHCR publication

Task: `2026-09-03-vault-signer-ghcr-publish`
Reviewer: independent Terra reviewer
Review basis: the completed task bundle, the relevant workflow diff, and the
stated validation and GitHub Actions evidence only.

## Observed evidence

- The task contract authorizes only a repository-owned GitHub Actions dispatch
  and publication of `ghcr.io/s1ns3nz0/node-operator/vault-release-signer`.
  It explicitly prohibits Terraform, AWS, Vault, EKS, deployment, merge,
  secret changes, and production access.
- The release workflow adds `vault-release-signer` to its existing matrix,
  pointing at `.ci/toolchains/vault-release-signer.Dockerfile`. Its existing
  release script invocation preserves the input-hash-controlled publish/skip
  path for every matrix entry.
- The stated checks passed: `scripts/ci/test-toolchain-image-release.sh`,
  `scripts/ci/test-vault-signer-toolchain-contract.sh`, the CodeBuild
  activation/signing/verification tests, `npm run harness:check`, and
  `git diff --check`.
- GitHub Actions run `33738717444` completed successfully at
  `a38872462cf411b5ab26bff63459eb594d4a6bb1`. Its signer job `100595348990`
  pushed both the commit-derived signer tag and `:main`, reporting manifest
  digest
  `sha256:3674b70a8c02a7fd0734e8e0d7c7f4f33fe7701f30b4c6f21569877721d55d07`
  for each.
- Direct Packages API readback was not available because the local GitHub
  token lacks `read:packages`; no token scope was changed.
- The recorded evidence reports no Terraform, AWS, Vault, or EKS action.

## Inference and conclusion

The workflow change is scoped to making the already-contract-tested signer
image eligible for the established content-addressed release mechanism. The
successful signer job and matching digest output support the conclusion that
the two published tags resolved to the same immutable manifest at the time of
the run. This is an inference from workflow output, not an independent
registry API readback.

Within the supplied evidence, publication stayed inside the authorized GHCR
boundary and did not evidence any prohibited infrastructure, secret, or
runtime action. The unavailable Packages API readback is a residual
observability limitation, not evidence of a failed publication, because the
workflow completed successfully and recorded the digest for both tags.
