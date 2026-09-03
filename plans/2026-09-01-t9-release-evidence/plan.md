# T-9: release-eligibility evidence

1. Define safe posture, SBOM, vulnerability, signature, and provenance contracts.
2. Add isolated collectors and retained JSON/SARIF-safe summaries.
3. Extend OPA decisions and fixtures for provenance, digest, builder, scan-age, and posture drift.
4. Add pinned scheduled/workflow collection without publishing or deploying.
5. Independently review and write a clean-room debrief.

## Execution boundary

The repository originally had no build artifact, signed digest, or provenance
statement. The collector and OPA contract were therefore tested only with
synthetic non-sensitive inputs.

## 2026-09-02 build binding update

The release unit is now a deterministic Kustomize release-bundle tarball. Its
source is materialized from the committed Git `HEAD` snapshot only, then its
Prysm and Nethermind overlays are rendered locally. The bundle emits an
immutable SHA-256 digest, a CycloneDX SBOM bound to that digest, and an
unsigned provenance input. It is a release candidate, not an eligible release:
an approved CI workflow must still obtain a verified signature, trusted
provenance, and completed vulnerability scan before the existing OPA decision
can pass. The build does not publish or deploy.
