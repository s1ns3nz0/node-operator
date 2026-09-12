# Decision: external supply-chain workflows

Use the official OpenSSF Scorecard action as a trusted-source scheduled
posture producer and GitHub's signed build-provenance action for release
bundles. Keep both controls separate from scanner and deployment workflows:
Scorecard measures repository posture, while SLSA provenance binds a concrete
release artifact to its source and builder. Existing Cosign, SBOM, scan, and
OPA gates remain authoritative for release eligibility.
