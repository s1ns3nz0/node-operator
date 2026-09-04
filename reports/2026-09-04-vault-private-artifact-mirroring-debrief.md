# Clean-room debrief: Vault private artifact mirroring

## Observed evidence

- The reviewed allowlist pins the Vault server, injector, and bootstrap toolchain source digests. It also pins the Vault 0.31.0 archive checksum and private ECR OCI manifest digest.
- The generic mirror workflow fails closed unless an existing immutable tag resolves to the approved digest. The chart workflow checksum-verifies its source archive, checks an existing immutable tag before pushing, and verifies the resulting ECR manifest digest.
- Recorded GitHub Actions runs for the three OCI artifacts and the corrected chart mirror completed successfully. Read-only ECR checks recorded digest parity for all runtime and toolchain images and confirmed the nested chart repository exists.
- Terraform binds the eventual CodeBuild Helm reference to the private chart manifest digest and grants only the chart-repository read permissions required for that verification.

## Inference and conclusion

No blocking defect was found. The evidence is sufficient for private delivery of the runtime images, bootstrap toolchain, and chart, conditional on the recorded workflow and ECR results. It does not authorize or establish a Terraform apply, CodeBuild run, Helm deployment, or Vault operation.

## Audit note

The evidence records immutable workflow commit IDs and run URLs to retain the linkage between reviewed workflow definitions and the observed mirror results.
