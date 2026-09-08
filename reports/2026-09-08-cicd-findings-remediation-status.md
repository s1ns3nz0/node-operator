# CI/CD remediation activation status

Date: 2026-09-08. Companion to the full `2026-09-08-cicd-optimization-redteam.md` assessment (DoD Guidebook v2.5, SSDF SP 800-218, SP 800-204D).

This is an implementation checkpoint, not a declaration that all HIGH/MEDIUM controls are active.

| Finding | Implemented / reviewed | Still required for closure |
|---|---|---|
| H1: trusted PR decision and protection | Exact PR-head check; trusted policy revision; trusted independent scanner execution instead of PR-produced artifact trust; fail-closed decision publication | Land reviewed workflow, prove positive and negative runs, then configure required check without weakening reviews. Private GitOps branch protection currently returns HTTP 403; environment variables alone do not replace protection. |
| H2: full-history secret scanning | Collector uses git-history scanning; untrusted head/base checkouts retain history | Publish reviewed immutable scanner image, verify history-canary rejection, update digest pins. Existing image embeds the old collector. |
| H3: deploy supply-chain acceptance | Approved source/digest binding, Cosign signature and provenance, fresh SBOM/SCA; downloaded chart hash matches the approved OCI manifest layer | Establish genuinely protected approval boundary and execute live private CD acceptance. Current SCA threshold covers fixable HIGH/CRITICAL (`--only-fixed`); it is not proof that unpatched vulnerabilities are absent. |
| H4: real private-service DAST | Narrow NetworkPolicies, public certificate-only trust installer, fixed signer GET `/upcheck` proxy; no direct DAST-to-signing API permission; real embedded-code routing and connection-close tests passed | Explicitly authorized deployment and live positive/negative connectivity tests. No runtime manifests applied in this checkpoint. |
| M1: release eligibility | Exact merged-main source, trusted workflow identities and required check set, merged PR-head evidence decision | Land and test permitted release and rejected ineligible source without bypassing source review. |
| M2: Checkov reconciliation | All Checkov findings now enter OPA; concrete IaC fixes; malformed exception expiry fails closed; exact resource/check exceptions | Review Terraform plans before any apply. Exceptions are accepted bounded risks, not implemented protections; expiry and production/DR triggers remain enforced. |

## Observed validation

- Final implementation commit `b601906`: hosted quality (`34182735198`), scanners (`34182735179`), policy (`34182735205`), policy-foundation (`34182735180`) and terraform (`34182735215`) passed.
- H1 scanner policy inputs are pinned to the trusted default-branch checkout. Semgrep, Gitleaks, OSV and Checkov local ignore/config replacement is rejected; inline scanner suppressions are disabled or surfaced as blocking evidence. NUL-delimited path handling covers nested and non-ASCII filenames.
- Terraform 4 modules validate successfully with AWS provider 5.100.0; formatting passed. Initialization used `-backend=false`; no remote state or resource apply.
- OPA: 67/67 passed. `npm run harness:check` and `npm run harness:verify` passed, including expected negative fixtures.
- GitOps H3 commit `f93751f`: hosted supply-chain verification run `34181792373` succeeded. Local negative tests reject changed chart contents even when the tag lookup still returns the approved manifest digest.
- H4 commit `f279cfa`: root independently reran the behavioral access contract successfully. Only GET `/upcheck` contacts the mock TLS upstream once; other GET paths and signing methods do not contact upstream.
- Actual Checkov 3.2.522 scan: 26 findings, zero findings lacking an exact registered check-ID/resource pair. These are not 26 passed checks. Detailed scope, rationale and expiry are in `docs/security/checkov-2026-09-08-disposition.md`.
- Read-only TLS probe: signer certificate is self-signed, CN `validator-hoodi-001-remote-signer`, no SAN. Verification against the existing public CA and exact short hostname succeeds. The proxy must keep CA and hostname validation; SAN reissuance is a separate custody ceremony, not permission to disable TLS validation.
- Independent Terra review approved the scoped M2 changes at `2b7a9b2`; live Terraform plans/applies and an actually issued OIDC claim remain unverified.

## Integration boundary

Source PR: https://github.com/s1ns3nz0/node-operator/pull/125

GitOps PR: https://github.com/s1ns3nz0/node-operator-gitops/pull/46

Further local H3/H4 review changes may not yet be in those remote heads. The primary integration owner records final commits and checks in the task bundle. No main merge, new image publication, review-protection relaxation, Terraform apply or DAST-resource deployment is asserted here.

A fresh clean-room debrief is still outstanding for this remediation task. Attempts to allocate a fresh review agent hit the session agent-thread limit; the previous optimization debrief is not a substitute for review of these new changes.
