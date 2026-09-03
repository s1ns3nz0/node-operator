# Clean-room debrief: Vault rollout readiness

## Scope reviewed

This clean-room review considered only the completed task bundle at
`plans/2026-09-03-vault-rollout-readiness/`, the diff from `1f3863b` to
`71e5b8e`, and the supplied validation outcomes.

## Observed facts

- The diff adds a digest-pinned Ubuntu signer-toolchain Dockerfile that
  downloads Vault 1.20.4 during image build, verifies the documented SHA-256,
  installs it in `/usr/local/bin`, and checks its installed version.
- The release-signing buildspec no longer downloads or extracts Vault at
  runtime. It requires the preinstalled Vault version to equal 1.20.4 before
  accepting release inputs, and uses the Vault CLI for Transit signing and
  verification.
- The added structural contract test asserts those image, version, checksum,
  runtime-download, signing, verification, and documentation boundaries.
- The GitOps documentation requires a selected image digest and rejects
  tag-only runtime configuration; it describes publishing, digest selection,
  and CodeBuild image wiring as separately authorized activation work.
- The signer structural test and the release-verification gate passed.
- The local signer image build and version parser passed.
- `npm run harness:check` passed.
- `npm run harness:verify` was not admitted: OPA, conftest, and shellcheck are
  unavailable locally, and no complete OSV evidence input is available. No
  bypass was added.
- No image publish, CodeBuild wiring, AWS, Vault, EKS, or GitHub workflow
  action occurred.

## Inferred future activation

The reviewed changes establish a local, non-secret readiness contract for a
future private CodeBuild-to-Vault signing path. They do not demonstrate that a
signer image has been published, that a digest has been selected and wired to
CodeBuild, or that private network, AWS authentication, Vault authorization,
or release-workflow prerequisites operate in a deployed environment.

Any activation remains separately authorized work and should include the
unadmitted policy-adapter validation with its required tools and complete OSV
input, plus environment-specific verification after approved provisioning.
