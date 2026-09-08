# DevSecOps Pipeline Red Team Report
**Date:** 2026-09-08
**Framework:** DoD Guidebook v2.5 + SSDF SP 800-218 + SP 800-204D

---

## 🔴 HIGH Severity (4 findings)

### H1: Security findings are not a required PR-head gate
- **Document:** NIST SP 800-218 PW.7.2, PW.8.2 / SP 800-204D §5.1.3
- **Current:** `CI Security / scanners` succeeds after evidence collection. The blocking OPA decision runs later under `workflow_run` and is absent from observed PR-head checks and required branch checks. A PR can satisfy the required `quality` and `scanners` checks without an enforced policy decision.
- **Fix:** Emit a trusted check run bound to `workflow_run.head_sha`, require that exact check in branch protection, and reject merge queues when the decision is absent or blocking. Add a negative integration test that introduces a scanner finding and proves the PR-head check fails.

### H2: Secret scanning does not inspect Git history
- **Document:** SP 800-204D §5.1.4 / NIST SP 800-218 PS.1.1
- **Current:** Checkout fetches full history, but the scanner invokes Gitleaks with `--no-git`; historical commits are not scanned.
- **Fix:** Run the pinned scanner with `gitleaks git --redact --exit-code 1 /workspace` for protected branch and release contexts, and retain only redacted counts and paths.

### H3: Deployment acceptance does not verify the published signature and SBOM
- **Document:** DoD DELIVER and DEPLOY required activities / NIST SP 800-218 PS.2.1, PS.3.2 / SP 800-204D §5.1.3
- **Current:** GitOps deployment acceptance checks Argo revision, health, and immutable image/chart binding. It does not verify the Cosign identity/provenance or re-run SBOM SCA for the deployed subject.
- **Fix:** Admit only a digest whose Cosign subject, issuer, workflow identity, source SHA, builder, and SBOM scan decision match the promoted GitOps revision; store a compact acceptance record.

### H4: DAST scope covers only the loopback health endpoint
- **Document:** DoD TEST and DEPLOY DAST activities / NIST SP 800-218 PW.8.2
- **Current:** The private DAST run passed with zero alerts, but the observed target was only `loopback-healthz`; Nethermind, Prysm, Vault, and validator-facing API behavior was not exercised.
- **Fix:** Define authenticated, read-only endpoint inventories per service, run the digest-pinned scanner inside the private boundary, and make the deploy decision consume a redacted per-target result.

---

## 🟡 MEDIUM Severity (2 findings)

### M1: Release tag protection does not establish release eligibility
- **Document:** NIST SP 800-218 PS.3.1 / SP 800-204D §5.1.4
- **Current:** The active tag rule prevents deletion and non-fast-forward updates, but does not require an approved source revision or security decisions before initial tag creation.
- **Fix:** Create releases only through the protected release environment from a commit whose required PR and release-integrity checks succeeded; restrict tag creation to that workflow identity.

### M2: IaC findings and exception records are not reconciled
- **Document:** NIST SP 800-218 RV.1.3, RV.2.1
- **Current:** Observed security evidence contains 43 Checkov findings, while the dated exception register contains a smaller reviewed set. Their disposition is not proven by the required PR checks.
- **Fix:** Reconcile every finding to a fixed commit or a bounded exception containing owner, rationale, issue, and expiry; fail closed on unmatched entries.

---

## 🟢 LOW Severity (0 findings)

No additional low-severity finding was retained; optimization-only issues were fixed in this change.

---

## ✅ Passing Controls (12 items)

- GitHub Actions are restricted to selected actions and full commit SHA pins.
- Workflow permissions are explicitly scoped; AWS access uses OIDC.
- SAST, dependency scanning, secret scanning, IaC scanning, and workflow scanning execute in CI.
- Source secret scanning and push protection are enabled.
- Release bundles are deterministic and bound to the source revision.
- CycloneDX SBOMs are generated and archived.
- This change analyzes the exact generated release SBOM with checksum-pinned Grype 0.118.0.
- High, critical, unknown, malformed, or invalid-database scan states fail closed.
- Retained SCA evidence contains counts and bindings, not raw package or CVE details.
- Release publication depends on the reusable integrity job.
- Release signing and SLSA-style provenance are present.
- Private CD and its limited loopback DAST execution have passed previously.

---

## NIST Control Mapping
| Control | SSDF | SP 800-204D | Status |
|---------|------|-------------|--------|
| Pinned build tools and actions | PO.3.2, PW.4.4 | §5.1.1, §5.1.2 | Pass |
| SAST and dependency analysis | PW.7.2, RV.1.2 | §5.1.1 | Pass |
| Release SBOM generation and SCA | PS.3.2 | §5.1.1, §5.1.3 | Fixed; Actions run pending |
| Artifact signature and provenance | PS.2.1, PS.3.1 | §5.1.3 | Pass at publish; deploy consumption open |
| Secret scanning | PS.1.1 | §5.1.4 | Partial; history gap open |
| PR security decision enforcement | PW.7.1, PW.8.2 | §5.1.3, §5.1.4 | Open |
| DAST and post-deploy scan | PW.8.2 | §5.1.1 | Partial |
| Vulnerability disposition | RV.1.3, RV.2.1 | §5.1.3 | Open |

---

## Summary
Total findings: HIGH=4 MEDIUM=2 LOW=0

Coverage counts use only fully verified required activities from the skill checklist: DEVELOP=1/2 (50%), BUILD=3/4 (75%), TEST=4/5 (80%), RELEASE=3/3 (100% after this change), DELIVER=3/4 (75%), DEPLOY=2/4 (50%). Partial DAST and deploy-time signature/SBOM checks are not counted as complete.
