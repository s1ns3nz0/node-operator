## Result

PR144's gRPC 1.83.2 Server and Agent candidates are now published to their
existing private ECR repositories, without rebuilding. Registry readback,
binary hashes and dependency exports match the exact reviewed local images.
This PR selects those new immutable candidates for the read-only verification
workflow and re-binds their existing narrow applicability proof. Injector is
unchanged. No running workload, IAM, PVC, validator or custody state changed.

## Fresh registry evidence and risk assessment

- Pinned Grype 0.118.0, DB 2026-09-09T06:31:00Z: each C0/H0/M3/U1.
- Raw scans and summaries retain the Unknown and blocked status. Separate
  decisions pass only GO-2026-5932 on x/crypto v0.56.0: affected OpenPGP imports
  are absent from the exact reviewed complete dependency inventories.
- Expiry remains 2026-10-09T00:00:00Z; no scope widening, new High exception,
  suppression, or generic release scan-attestation relaxation.
- Medium BusyBox findings remain visible; these candidates are not yet approved
  for live rollout. Image hashes and manual exports do not establish a trusted
  GitHub build. Honest signing/verification and HA/KMS/auth/admission checks
  remain separate gates.

## Verification

Both remote scans and separate applicability evaluations passed. ShellCheck,
source pin regression, 7 scan tests, 9 applicability tests, wrapper/collector
negative contracts, harness validation and all policy adapters passed.
Independent Terra review covered publication boundaries and applicability
gating. Original failure evidence is retained: Docker Desktop selected a
macOS keychain helper unavailable in the Linux scanner. Portable temporary
registry auth fixed the retry; existing Server publication was not repeated.
Temporary auth directories were removed.

The task-scoped publisher is intentionally fixed to these exact two images,
repositories and immutable tag; it is not a general release workflow. It
requires explicit authorization, rejects tag conflicts and verifies equal
digest retries. No image signing or fictitious CI build provenance is claimed.

After merge: dispatch existing main-only Vault Runtime Candidate Verification.
Do not deploy from this PR alone.
