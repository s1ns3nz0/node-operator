## Summary

Connect the reviewed package-closure proof to the three frozen Vault runtime
candidates. No image rebuild, signing, deployment, IAM or custody change.

The raw Grype output and `scan-summary.json` remain unchanged (including
Unknown=1 and status=blocked). The workflow gates on a **separate**
`applicability-decision.json`, not a rewritten clean scan.

## Risk assessment

- Only GO-2026-5932 / golang.org/x/crypto v0.56.0 / Unknown is eligible, on the
  three committed digest+binary+dependency-hash combinations.
- Official advisory scope is the unmaintained openpgp package tree, absent
  from these complete reviewed dependency closures. The stripped-binary
  scanner warning alone is not used as proof.
- Read Server/Injector closure from their frozen images. Preserve the existing
  public Agent build export once, with its exact runtime-binary/hash binding.
- Require the live advisory to equal the pinned reviewed advisory. Expiry:
  2026-10-09T00:00:00Z. Missing evidence, advisory/image drift, expiry, new
  Unknown or any Critical/High fails closed. Medium findings remain visible.
- Hashes bind manually reviewed build metadata to frozen bytes; this is not a
  claim that GitHub built these images, or proof of a trusted compiler.
- General Grype configuration and release scan-attestation verification are
  unchanged. Signing/provenance and live Vault HA/KMS/auth/admission gates
  remain separate requirements.

## Validation

Actual artifacts from run34314957185 are replayed with fresh offline metadata
extraction from all three frozen images and the current official advisory.
Synthetic negative tests cover digest/binary/closure/identity/advisory drift,
expiry, affected package presence, additional Unknown and severity changes.
The task evidence records final check and independent-review outcomes.

After merge, rerun the manual read-only verification workflow. This PR does
not authorize a live rollout or convert the raw Unknown into a zero count.
