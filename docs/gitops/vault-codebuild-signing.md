# Private CodeBuild and Vault Transit signing boundary

Release signing runs in an AWS CodeBuild project attached to the private EKS
subnets. GitHub Actions may assume only the release-runner role through OIDC
and may start the project; it cannot read Vault keys or write release assets.

The CodeBuild service role is limited to the project artifacts bucket, VPC
network interfaces, and the Vault signer endpoint. The signer authenticates
the build with a short-lived workload identity and calls Vault Transit
`sign/<key>`; the private key is never exported. `read`, `update`, `delete`,
and key-management capabilities are denied.

The signed payload is the digest-bound in-toto provenance statement. CodeBuild
immediately calls Transit `verify` on the returned signature and emits a
non-sensitive `release-verification.json`. It binds the verified signature to
the bundle digest, provenance-file digest, provenance subject digest, source
revision, builder identity, and CodeBuild build ID. The release gate recomputes
the local digests and fails closed if that result is absent, invalid, or
inconsistent. Vault tokens, static AWS credentials, and key material are not
release artifacts.

No AWS resources, Vault keys, policies, or credentials are created by this
document. Terraform implementation requires explicit approval after plan
review.

## Prebuilt signer image boundary

The signer build uses the reviewed `vault-release-signer` toolchain image. It
contains Vault `1.20.4`, installed from the release archive only after the
documented SHA-256 is verified. The buildspec checks that exact preinstalled
version before it accepts any release input; it never downloads or extracts
Vault at build time.

The generic toolchain release process derives the image input label from the
Dockerfile and its declared inputs. An image digest, rather than a mutable tag,
must be selected for the CodeBuild environment. Tag-only runtime configuration
is not accepted.

Publishing the image, selecting its digest, and wiring that digest into the
CodeBuild project are a separately authorized activation follow-up. This
contract deliberately does not change the current CodeBuild image or create
any AWS, Vault, EKS, or GitHub Actions resource.
