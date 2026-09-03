# T-9 clean-room debrief

## Observed evidence

- The bundle builder materializes its release boundary from Git `HEAD`, renders
  Prysm and Nethermind locally, creates a deterministic tarball, and records
  its SHA-256 digest.
- The generated CycloneDX v1 SBOM is required to bind
  `metadata.component.version` to that digest. Collector tests explicitly
  reject mismatched SBOM digests and unsupported SPDX input.
- Recorded checks report passing bundle and collector tests, including
  deterministic bytes, source snapshot materialization, rendered paths,
  digest/SBOM linkage, and sensitive-marker exclusion.
- The collector writes compact evidence envelopes and keeps raw source reports
  in a temporary private directory.
- `harness:check` passed. `harness:verify` is recorded as partial because OPA,
  Conftest, and ShellCheck are unavailable; the pre-existing normalizer fixture
  remains intentionally incomplete.
- No deploy, publish, merge, AWS access, production access, or secret changes
  are recorded.

## Inference

The candidate is intentionally not release-eligible. It remains an unsigned
local artifact because Cosign and Grype are absent, no approved signing
identity or trusted CI provenance exists, and no completed vulnerability scan
exists. The documented design therefore relies on OPA to remain fail-closed
until trusted signature, provenance, and scan evidence are supplied.

The build and collector contracts provide useful local binding and boundary
checks, but they do not substitute for trusted CI attestations or the
unavailable harness-policy adapters.
