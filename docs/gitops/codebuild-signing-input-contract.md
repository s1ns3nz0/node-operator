# CodeBuild signer input and output contract

This is the proposed activation contract for the private CodeBuild signer. It
documents the boundary that a separately approved Terraform and release
workflow change must implement; it does not claim that the current project or
workflow is wired this way.

## Immutable signer input

The release runner creates exactly one immutable source archive for a source
revision. Its S3 object key is SHA-named:

```
s3://<input-bucket>/release-input/sha256/<source-revision>.zip
```

`<source-revision>` is the full immutable Git commit SHA recorded in
`provenance-input.json`. The archive is written once under the release-input
prefix and must not use a mutable location such as `bootstrap.zip`, a branch,
or a tag. The archive root contains exactly these reviewed files:

```
node-operator-release-bundle.tar
node-operator-release-bundle.sha256
provenance-input.json
buildspec-release-sign.yml
```

The checksum file must bind the bundle bytes, and the provenance subject and
source revision must bind the same bundle and Git SHA. The reviewed
`buildspec-release-sign.yml` is carried in that archive. CodeBuild must select
that archive-local buildspec explicitly; no hidden project-level, external
S3, branch, or tag buildspec is permitted.

The CodeBuild invocation uses that same `<input-bucket>` and exact
`release-input/sha256/<source-revision>.zip` value for its S3 source-location
override. The source-version is the same `<source-revision>`. A mismatch among
the archive key, source-location override, source version, bundle checksum,
or provenance source revision fails the release.

## Verification output and consumer gate

CodeBuild reads only the declared source archive and produces a single output
package. It contains the four non-secret files needed by the existing release
verification gate:

```
node-operator-release-bundle.tar
node-operator-release-bundle.sha256
provenance-input.json
release-verification.json
```

`release-verification.json` must bind the bundle digest, provenance-file
digest and subject digest, source revision, and builder identity. Its evidence
also includes the CodeBuild build ID. The release consumer extracts this
package and calls `scripts/ci/verify-release-signature.sh` on the complete
directory. It gates
on `release-verification.json`, not raw `signature.json` or `verify.json`.
Raw signature/verification response files, Vault tokens, static credentials,
and key material are never output artifacts. The verifier accepts the
format-bound Transit signature inside `release-verification.json` only as the
non-secret evidence required to prove that Vault verified the payload.

The selected CodeBuild container image must be a digest, never a tag-only
reference.

## Activation preconditions

This contract is intentionally not a current-runtime conformance assertion.
The future activation must be an approved atomic change that updates all of
the following together after plan review:

1. Terraform `aws_codebuild_project` source type, source-location override,
   archive-local buildspec selection, artifacts, and digest-pinned signer
   image.
2. `release.yml` input archive packaging, immutable S3 upload, CodeBuild
   invocation, output download, and `verify-release-signature.sh` consumer
   gate.

It must not be activated until the private runner, Vault route, and dynamic
identity preconditions are live and independently verified.
