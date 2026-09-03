# Clean-room debrief: CodeBuild signing input contract

## Scope reviewed

This debrief was prepared from the task bundle at
`plans/2026-09-03-codebuild-signing-input-contract/`, the change range
`2d6ef33..7eb79ec`, and the recorded check outcomes only. No runtime,
infrastructure, workflow, cloud, Vault, or release-system state was inspected
or changed.

## What the change establishes

The change documents and structurally tests a proposed, fail-closed interface
for a future private CodeBuild signer:

- One immutable, SHA-named source archive contains the reviewed release bundle,
  checksum, provenance input, and archive-local signing buildspec.
- The CodeBuild invocation is specified to use the exact archive location and
  source revision, with mismatches treated as release failures.
- The signing output is limited to the bundle, checksum, provenance input, and
  `release-verification.json`; raw signing responses and secret material are
  excluded.
- The existing verification gate is checked for compatibility with that output
  layout, and the signer image is specified to be digest-pinned.

The added structural test validates those contract boundaries and the existing
buildspec/verifier artifact relationship. The recorded targeted contract test,
release-verification gate, harness check, and diff check all passed.

## Contract versus current implementation

This is a future activation contract, not evidence that the repository's
current CodeBuild configuration or release workflow implements it. The reviewed
diff adds documentation, a structural test, its package-script entry, and task
evidence. It intentionally makes no Terraform, `release.yml`, buildspec,
AWS, Vault, or other runtime activation change.

Consequently, the contract's archive source selection, immutable upload,
CodeBuild override, archive-local buildspec selection, output retrieval, and
consumer invocation remain requirements for a separately approved activation;
they are not current-runtime claims.

## Required future activation boundary

Activation must be atomic after plan review. One approved change must align the
Terraform `aws_codebuild_project` source and artifacts settings, archive-local
buildspec selection, and digest-pinned image with the `release.yml` archive
packaging, immutable S3 upload, CodeBuild invocation, output download, and
`verify-release-signature.sh` gate. Activating only one side would leave the
source, buildspec, or consumer contract inconsistent.

The documented preconditions also remain binding: the private runner, Vault
route, and dynamic identity must be live and independently verified before
activation.

## Clean-room conclusion

The delivered change is appropriately limited to defining and checking a
non-secret contract. Its verification evidence supports the contract and its
current verifier/buildspec compatibility, not deployment or live-system
conformance. No prohibited action is represented in the reviewed diff.
