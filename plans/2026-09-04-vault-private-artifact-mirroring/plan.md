# Vault private artifact mirroring

1. Verify the existing bootstrap toolchain source digest and chart checksum.
2. Add only the reviewed bootstrap source digest to the allowlist and validate the mirror contracts.
3. Publish/dispatch the reviewed toolchain workflow, then mirror the approved toolchain, Vault server, and injector digests to the existing Vault ECR repository and verify them.
4. Check whether the Terraform-owned nested Helm OCI destination exists. Do not create it outside Terraform; record it as a precondition gap if absent.
5. Record non-sensitive workflow and digest evidence, then obtain an independent clean-room review.
