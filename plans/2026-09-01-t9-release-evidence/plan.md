# T-9: release-eligibility evidence

1. Define safe posture, SBOM, vulnerability, signature, and provenance contracts.
2. Add isolated collectors and retained JSON/SARIF-safe summaries.
3. Extend OPA decisions and fixtures for provenance, digest, builder, scan-age, and posture drift.
4. Add pinned scheduled/workflow collection without publishing or deploying.
5. Independently review and write a clean-room debrief.

## Execution boundary

The repository has no build artifact, signed digest, or provenance statement at
T-9 implementation time. The collector and OPA contract are therefore tested
only with synthetic non-sensitive inputs. A later build task must invoke the
collector with its produced artifact digest and attestation inputs; it must not
publish or deploy as part of that invocation.
