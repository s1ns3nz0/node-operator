## Honest signed verification, not fabricated build provenance

Adds opt-in `sign_evidence=true` to the main-only Vault verification workflow.
Default behavior stays unsigned/read-only. A separate job depends on successful
Server, Agent and Injector verification, rechecks trusted source/PR decisions,
and downloads only the current run's evidence. It does not acquire AWS
credentials, write ECR, rebuild images, alter IAM or deploy workloads.

The signed statement binds all three immutable subjects, current source/run/
attempt, complete evidence hashes and policy hashes. It explicitly records
build provenance as not established and deployment authorization as false.
Cosign uses GitHub OIDC to produce a detached Sigstore bundle; this is not an
OCI registry signature or an SLSA build attestation.

## Fail-closed producer and consumer

- Replay exact-candidate applicability and compare the stored decision.
- Preserve raw Unknown findings and blocked raw summaries; no new exception.
- Reject wrong run/attempt, altered/missing/symlinked evidence, changed policy,
  scans older than 24h, databases older than 48h and expired assessments.
- Require exact workflow identity, issuer, SHA, repository, main ref and manual
  trigger; never accept test keys, regex identity or skipped tlog checks.
- Upload a complete verified bundle only after both signature and semantic
  checks pass, with 30-day retention. Failed-job-only reruns fail on stale
  attempt metadata; rerun all verification jobs instead.

## Verification and risk assessment

Synthetic content/negative tests, nine workflow/identity contract mutations,
crypto-failure short-circuit, source eligibility tests, ShellCheck and all
harness policy adapters passed. Real Cosign 3.1.2 offline synthetic blob
roundtrip and tamper rejection passed in pinned Docker, and now run in CI.
Actual run34330457626 evidence replay passed using separate copied fixtures
with explicitly synthetic new-format context. Independent Terra review passed.

No hosted OIDC signing is claimed yet: merge, then dispatch the opt-in run and
verify its actual bundle. The scoped redteam report identifies remaining
historical build-provenance limits, GitOps-side promotion enforcement and
longer-term evidence archival. This change does not authorize deployment or
relax the generic release scan-attestation verifier. See task redteam.md and
docs/operations/vault-runtime-signed-evidence.md for the consumer contract.
