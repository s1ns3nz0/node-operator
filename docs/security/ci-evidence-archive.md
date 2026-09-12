# Long-term CI evidence archive

The `CI Evidence Archive` workflow archives only a successful, exact-head
`CI Evidence Gate` artifact. It never uploads a workspace, raw scanner output,
credentials, Vault material, or recovery shares.

Terraform creates the following resources when
`enable_ci_evidence_archive = true` (the default):

- a versioned S3 bucket with Compliance Object Lock and SSE-KMS;
- a dedicated KMS key with automatic rotation;
- an exact GitHub OIDC role scoped to the `ci-evidence-archive` environment;
- an IAM policy limited to `s3:PutObject` below `ci/*`, plus read-after-write
  verification.

After applying Terraform, configure these two repository/environment variables
on the protected GitHub environment named `ci-evidence-archive`:

```text
CI_EVIDENCE_ARCHIVE_BUCKET=<terraform output ci_evidence_archive_bucket_name>
CI_EVIDENCE_ARCHIVE_ROLE_ARN=<terraform output ci_evidence_archive_role_arn>
```

The workflow downloads the exact OPA evidence artifact, validates that the
decision has `block=0` and `require_approval=0`, builds a deterministic
manifest, signs it with Cosign keyless signing, verifies the Sigstore bundle,
and uploads the evidence plus `manifest.json` and
`manifest.sigstore.json` beneath:

```text
s3://<bucket>/ci/<subject-sha>/<workflow-run-id>/
```

The S3 bucket's Object Lock is the retention control. Cosign proves who signed
the manifest and what bytes were signed; SSE-KMS protects the stored bytes.
Both controls are required for retrieval to be trusted.
