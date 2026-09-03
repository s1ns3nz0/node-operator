# Private CodeBuild and Vault Transit signing boundary

Release signing runs in an AWS CodeBuild project attached to the private EKS
subnets. GitHub Actions may assume only the release-runner role through OIDC
and may start the project; it cannot read Vault keys or write release assets.

The CodeBuild service role is limited to the project artifacts bucket, VPC
network interfaces, and the Vault signer endpoint. The signer authenticates
the build with a short-lived workload identity and calls Vault Transit
`sign/<key>`; the private key is never exported. `read`, `update`, `delete`,
and key-management capabilities are denied.

The signed payload is the digest-bound in-toto provenance statement. The
release gate verifies the signature, artifact digest, source revision, builder
identity, and SBOM digest before publication or Argo CD deployment.

No AWS resources, Vault keys, policies, or credentials are created by this
document. Terraform implementation requires explicit approval after plan
review.
