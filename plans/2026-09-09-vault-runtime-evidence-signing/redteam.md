# DevSecOps Pipeline Red Team Report

**Date:** 2026-09-09
**Framework:** DoD Guidebook v2.5 + SSDF SP 800-218 + SP 800-204D

Scope: step2 Vault verification signing, not a certification or a full live
deployment audit. All framework groups below were considered; deferred phases
are not reported as implemented. No paid GitOps protection setting is proposed.

## 🔴 HIGH Severity (2 findings)

### H1: Consumer-side promotion enforcement is not yet integrated
- **Document:** DoD phase tables DELIVER/DEPLOY; SP 800-204D §5.1.3; SSDF PS.2.1.
- **Current:** This source PR supplies signature/content verification, but does
  not wire GitOps promotion to it or prove post-deployment acceptance.
- **Fix:** In the GitOps repository, call the trusted verifier with independently
  approved revision/run/attempt, match each proposed image to signed subjects,
  require Argo health plus private security/operational acceptance, and retain
  the CD decision. Deferred to the rollout step; deployment remains forbidden.

### H2: Historical candidate build provenance is not established
- **Document:** SP 800-204D §5.1.1 and §5.1.3; SSDF PS.3.1.
- **Current:** Candidates are manually built; a GitHub scan cannot certify their
  historical compiler environment. A fake SLSA predicate would mislead consumers.
- **Fix:** Explicitly sign only verification facts with exact binary/dependency
  bindings. Preserve `build_provenance:not_established`. Before full production
  assurance, use a separately reviewed trusted build or documented manual-build
  acceptance. This PR does not claim to close historical build provenance.

## 🟡 MEDIUM Severity (1 finding)

### M1: Evidence retention is bounded, not a durable release archive
- **Document:** SP 800-204D §5.1.3; SSDF RV.1.1 and RV.1.3.
- **Current:** GitHub artifacts retain complete evidence for 30 days. The bundle
  cannot be independently re-evaluated after evidence is lost.
- **Fix:** Archive the verified bundle and complete public evidence into the
  separately approved release store before expiry. Keep fresh scan requirements;
  archival retention must not bypass the 24h observation / 48h database limits.

## 🟢 LOW Severity (0 findings)

No additional low-severity finding in this bounded change.

## ✅ Passing Controls (12 items)

1. Explicit opt-in; default verification makes no signatures.
2. Main-only aggregate signing after all three verification jobs succeed.
3. Existing trusted source-eligibility checks include source CI and PR decision.
4. Exact same run and attempt, no latest-artifact selection.
5. Checksum-pinned tools and SHA-pinned Actions on ephemeral runners.
6. Separate OIDC signing job; no AWS credential request or ECR write.
7. Exact signer identity, issuer, repository, SHA, main ref and trigger checks.
8. No insecure transparency-log/certificate bypass in production verifier.
9. Complete evidence/policy hashes and three immutable subjects are bound.
10. Raw scans retained; narrowly scoped, expiring applicability is replayed.
11. Freshness, missing/altered evidence and symlink checks fail closed.
12. Semantic and synthetic cryptographic negative tests; artifacts upload only
    after successful signature verification, not on failed security gates.

## NIST Control Mapping

| Control area | SSDF | SP 800-204D | Status |
|---|---|---|---|
| Process, ownership, tool/IaC controls | PO.1.1, PO.2.1, PO.3.1–2, PO.4.1, PO.5.1 | §5.1.1–2 | Harness/pins/source gate; no IaC mutation |
| Source protection and review | PS.1.1, PW.7.1–2 | §5.1.4 | Existing source CI required; not a new source scanner |
| Integrity and evidence | PS.2.1, PS.3.1–2 | §5.1.3 | Implemented signature/content path; H1/H2/M1 remain |
| Secure environment, dependencies | PW.4.1, PW.4.4 | §5.1.1 | Ephemeral jobs, no candidate execution in signing job, SCA |
| Tests and executable review | PW.8.1–2, PW.9.1 | §5.1.1 | Local contracts plus independent review; live DAST deferred |
| Monitor, identify, track, assess | RV.1.1–3, RV.2.1, RV.3.1 | §5.1.3 | Raw/decision history; narrow assessment; no disclosure-policy change |

## Summary

Total findings: HIGH=2 MEDIUM=1 LOW=0. These are explicit remaining release
boundaries, not new exemptions or permission to deploy.

Coverage: DEVELOP=N/A BUILD=N/A TEST=N/A RELEASE=N/A DELIVER=N/A DEPLOY=N/A.
Percentages are not inferred for a partial workflow. Phase/tool coverage:

- DEVELOP: existing `ci-security.yml` / trusted collector cover Semgrep, Gitleaks,
  OSV, Zizmor and Checkov; source eligibility checks their trusted result. The
  current collector requests full Git history; old remediation prose is not
  treated as proof of current live scanner-image content.
- BUILD: no rebuild here; existing release-integrity workflow handles general
  reproducibility/SBOM checks. Candidate build assurance is H2, not silently passed.
- TEST: candidate runtime identity/version, Syft, Grype, applicability and unit/
  regression checks exist; API/DAST/system acceptance remains operational scope.
- RELEASE: this change adds go/no-go signed evidence, not an image release.
- DELIVER: ECR subjects already immutable; GitOps consumer gate remains H1.
- DEPLOY: Argo/private DAST/monitoring are separately owned by GitOps and the
  operations contracts; no live pass asserted. SCA must be revalidated there.

Universal hygiene and job dependencies were checked: no untrusted event text in
shell commands, floating Actions, unverified curl-to-shell, hardcoded secrets,
security `continue-on-error`, broad write token, or independent ungated signing
job was introduced. Default Sigstore public signing services receive only the
public verification statement/signing identity, never Vault data.

Sources: [NIST SP 800-204D](https://csrc.nist.gov/pubs/sp/800/204/d/final),
[Sigstore CI signing](https://docs.sigstore.dev/quickstart/quickstart-ci/).
Mappings are review references, not an assertion that every cited publication
mandates these exact GitHub implementation details.
