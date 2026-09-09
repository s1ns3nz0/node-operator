# DevSecOps Pipeline Red Team Report

**Date:** 2026-09-08
**Framework:** DoD Guidebook v2.5 + SSDF SP 800-218 + SP 800-204D

Scope: unpublished `validator-signing-fence-image.yml` at checkpoint `0f46024`
and its proposed evidence validator. This is a scoped engineering review, not
a certification or a claim that the repository lacks controls elsewhere.

## 🔴 HIGH Severity (3 findings)

### H1: Evidence assertions are not authenticated evidence

- **Document:** [SP 800-204D §5.1.3](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-204D.pdf); [SSDF PS.2.1](https://nvlpubs.nist.gov/nistpubs/specialpublications/nist.sp.800-218.pdf).
- **Current:** The proposed verifier accepts caller-created JSON containing
  `status: verified`, a claimed issuer, and a claimed scan age. Matching these
  fields cannot establish a real signature, scan execution, or freshness.
- **Fix:** Treat this as policy-input lint only. A trusted collector must verify
  signatures/attestations against the exact registry digest, expected workflow
  identity and source revision, and bind authenticated scan timestamps/results.
  Missing authenticated evidence must deny promotion, including valid-shaped
  fabricated fixtures. Do not label schema acceptance deployable.

### H2: Build publication lacks the artifact security chain

- **Document:** [DoD Guidebook v2.5, Table 1 and Table 14](https://dodcio.defense.gov/Portals/0/Documents/Library/DevSecOpsActivitesToolsGuidebook.pdf); SP 800-204D §§5.1.1–5.1.3; SSDF PO.4.1, PS.2.1, PS.3.2, PW.4.4, RV.1.2.
- **Current:** The workflow runs Go tests, builds and pushes. It does not create
  or validate an SBOM, scan the built image, create/verify provenance and
  signatures, or archive those results. A digest and input-hash summary are
  not substitutes. The input hash also omits the Dockerfile.
- **Fix:** Build into a non-promoted location, generate and validate an SBOM,
  scan that exact digest, sign/attest the source and complete build inputs,
  verify the resulting artifacts, and archive sanitized evidence. Require all
  checks before promotion; test missing evidence and nonzero scanner exits.

### H3: Delivery and runtime acceptance remain unproven

- **Document:** DoD Guidebook v2.5, Table 1 and TEST/DELIVER/DEPLOY phase activities; SSDF PW.8.2, RV.1.1; SP 800-204D §5.1.3.
- **Current:** This image has no demonstrated private-cluster deployment,
  post-deployment security test, recurring image reassessment, or live duty
  recovery evidence. Unit tests do not prove network-policy enforcement.
- **Fix:** After authenticated promotion, test exact-digest admission, direct
  signer bypass denial, Pod-identity changes, Lease/API failure, and bounded
  existing connections. Record one duty before interruption and one after
  recovery. Keep activation denied until these prerequisite controls pass.

## 🟡 MEDIUM Severity (2 findings)

### M1: Host Go test toolchain is not pinned by the workflow

- **Document:** SSDF PO.3.2; SP 800-204D §5.1.1.
- **Current:** Tests use runner-provided `go`; the image compiler uses a separate
  digest-pinned Go builder. Local tests used another version.
- **Fix:** Execute tests with the reviewed builder/toolchain and scan its actual
  compiled output; do not infer image security from a local test pass.

### M2: Protected environment declaration is not protection evidence

- **Document:** SSDF PO.2.1, PO.4.1; SP 800-204D §§5.1.2, 5.1.4.
- **Current:** The YAML names an environment, but its live restrictions and
  exact image-promotion authorization have not been verified for this workflow.
- **Fix:** Read back effective environment/OIDC/repository restrictions and
  current-head review policy. Preserve the user's paid-plan exception; do not
  fabricate a branch-protection success flag to satisfy a JSON schema.

## 🟢 LOW Severity (0 findings)

None assigned in this scoped pass.

## ✅ Passing Controls (6 items)

- Checkout is SHA-pinned with credential persistence disabled.
- Explicit read-only contents and OIDC permissions are declared.
- Cloud credentials are short-lived and masked; no static cloud key is embedded.
- Main-ref restriction precedes cloud publication.
- Unit tests precede the push and shell failures stop the job.
- The runtime is non-root/scratch; fence and Prysm repositories are separated.

These are source-observed controls, not live-enforcement attestations. No direct
event-body interpolation, `curl | bash`, or ignored security failure was found
in the scoped workflow. It has one sequential job, so no job dependency graph
artifact is necessary or created.

## NIST Control Mapping

| Control group | SSDF | SP 800-204D | Status |
|---|---|---|---|
| Process/roles/build/gates/IaC | PO.1–PO.5 | §5.1.1 | Roles and IaC exist; promotion gate incomplete |
| Source/integrity/archive | PS.1–PS.3 | §§5.1.3–5.1.4 | Repository history scanning observed; artifact proof missing |
| Dependencies/review/testing | PW.4, PW.7–PW.9 | §§5.1.1–5.1.2 | Unit tests present; image/runtime security tests incomplete |
| Monitoring/triage/root causes | RV.1–RV.3 | §5.1.3 | No fence-image lifecycle evidence yet |

Tool-category check: GitHub Actions, Go tests and ECR are present. Repository
SAST/secret checks exist outside this workflow; built-image dependency scanning,
SBOM, runtime security tests and evidence archival are not connected here.

## Summary

Total findings: HIGH=3 MEDIUM=2 LOW=0.
Coverage: DEVELOP=partial; BUILD=partial; TEST=partial; RELEASE=incomplete;
DELIVER=unverified; DEPLOY=unverified. Percentages are not assigned because
source inspection is not measured end-to-end execution coverage.

Disposition: local-only work may continue; image promotion and activation are
not approved by this report. No graph, debrief, deployment or secret operation
was performed for this review.
