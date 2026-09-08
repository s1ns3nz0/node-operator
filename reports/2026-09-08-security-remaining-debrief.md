# Remaining security remediation: clean-room debrief

## Scope and method

This fresh review read only the completed task bundle
`plans/2026-09-08-security-remaining/`, its uncommitted status report, the
source diff from `3276b3b4f31eb548e1cb76a7c8feb27b03559414` through `c541877`,
and GitOps commit `944a020`. It also inspected the changed source, GitOps DAST
runner, and the checks named below. It did not inspect prior task bundles,
cloud state, GitHub/CI state, images, secrets, raw plans, or external logs; it
made no external change.

## Conclusion

No new high-confidence security or correctness blocker was found in the
reviewed diffs. The supplied evidence supports **only the primary access-log
CRR change as activated and verified**. It does not support activation claims
for bootstrap reconciliation, DAST, scanner-image correction, PR-gate
enforcement, GitOps protection, or any broader compliance conclusion.

The one documentation inconsistency is non-blocking but should be corrected in
a later reviewed change: `docs/operations/access-log-replication.md` still
calls CRR a proposal with no authorized cloud change, while the task evidence
and status report record its approved application and canary readback. The
status/evidence record is the basis for the activated classification below.

## Observed state, separated by activation

### Activated and evidenced: primary access-log CRR only

- The bundle records a saved plan with exactly six creates and no update,
  delete, or replacement; it records application of the two roles, two inline
  policies, and two replication configurations.
- The four configured rules are reported enabled, with delete-marker
  replication disabled. Both retained, non-secret zero-byte canaries are
  reported `COMPLETED`; destination readback is reported as same-version
  `REPLICA` objects with AES256 encryption. A targeted post-apply plan is
  recorded as having no managed change.
- The source configuration scopes source reads and destination writes to the
  four documented prefixes, uses distinct S3 service roles, excludes KMS,
  ownership override, delete replication, and reciprocal replication, and
  depends on source/destination versioning and its inline role policy. The
  focused Terraform contract passed locally.
- The supplied Checkov observation is **not clean**: 954 passed, 23 failed,
  and 6 skipped. The two terminal-replica `CKV_AWS_144` deviations and four
  S3-access-log SSE-S3 `CKV_AWS_145` deviations are exact, dated proposed
  exceptions. Regional DR limitations for state, validator audit, and Vault
  snapshot remain separate accepted limitations.

### Prepared or reviewed but unactivated

- **Bootstrap:** the module adds legacy bucket/key inputs, exact same-account
  role checks, restricted S3 CMK-use statements, and an import-only private
  copied-module runbook. No import, state/backend migration, CMK migration, or
  apply is evidenced. The five-resource inventory must not be generalized into
  ownership of any other bootstrap/foundation/ops resource.
- **DAST source and GitOps:** source manifests introduce fixed GET-only proxies
  and narrow network policies; GitOps `944a020` renders a disposable job with
  three HTTP probes, one separately labelled Nethermind TCP reachability probe,
  CA/hostname verification for Vault, bodyless HAR import with
  `sendRequests=false`, and compact v2 evidence. These are local contract and
  behavioral results only. The changes are not promoted/deployed, the public
  CA ConfigMaps are not installed, the pinned image was not exercised, and no
  private-cluster run exists. Nethermind's check remains reachability only, not
  JSON-RPC/Engine API or general service-health coverage.
- **CI/scanner governance:** the source OSV command order is corrected and the
  workflow-trigger exception is exact and expiring. Bundle evidence says the
  active immutable scanner still embeds the predecessor command, so trusted
  evidence fails closed. PR 128 review/merge, automatic image publication,
  digest verification, a separately reviewed pin promotion, hosted exact-head
  positive/negative proof, and required-check activation remain outstanding.
- **GitOps branch protection:** remains unavailable on the current private
  repository plan; no billing or visibility change is evidenced or authorized.

## Checks performed in this debrief

```text
source: scripts/ci/test-access-log-replication.sh               PASS
source: scripts/ci/test-bootstrap-state-reconciliation.sh       PASS
source: scripts/ci/test-private-dast-access-contract.sh         PASS
source: scripts/ci/test-ci-security-evidence-contract.sh        PASS
source: scripts/ci/test-policy.sh                               PASS (69/69)
source: npm run harness:check                                   PASS (84 graphs)
source: npm run harness:verify                                  PASS (policy adapters; expected insecure fixtures were rejected)
source: git diff --check base..HEAD                             PASS
GitOps: scripts/test-private-dast-contract.sh                   PASS
GitOps: scripts/test-private-cd-supply-chain-contract.sh        PASS
GitOps: scripts/test-publish-oci-contract.sh                    PASS
GitOps: git diff --check 944a020^ 944a020                       PASS
```

These checks establish static/rendered local behavior only. They do not verify
AWS application/readback, S3 continued replication or recovery, deployed
network-policy enforcement, certificate availability/compatibility, DAST image
behavior, GitHub event semantics, hosted required checks, branch protection,
or a published scanner digest. The AWS/PR/Checkov observations above are
bundle-supplied evidence, not independently re-observed here.

## Preserved framework mapping baseline

The following is the prior DevSecOps red-team mapping baseline, retained
without a new score or compliance assertion. This task's CRR evidence does not
change an overall framework status; unactivated work must not be counted as
implemented evidence.

| Control | SSDF | SP 800-204D | Baseline status |
| --- | --- | --- | --- |
| Pinned build tools and actions | PO.3.2, PW.4.4 | 5.1.1, 5.1.2 | Pass |
| SAST and dependency analysis | PW.7.2, RV.1.2 | 5.1.1 | Pass |
| Release SBOM generation and SCA | PS.3.2 | 5.1.1, 5.1.3 | Fixed; Actions run pending |
| Artifact signature and provenance | PS.2.1, PS.3.1 | 5.1.3 | Pass at publish; deploy consumption open |
| Secret scanning | PS.1.1 | 5.1.4 | Partial; history gap open |
| PR security decision enforcement | PW.7.1, PW.8.2 | 5.1.3, 5.1.4 | Open |
| DAST and post-deploy scan | PW.8.2 | 5.1.1 | Partial |
| Vulnerability disposition | RV.1.3, RV.2.1 | 5.1.3 | Open |

The baseline practice-group framing also remains unchanged: PO.1.1, PO.2.1,
PO.3.1, PO.3.2, and PO.5.1 have recorded controls; PO.4.1 remains open at PR
enforcement. PS.1.1 is partial; PS.2.1 and PS.3.1 pass at publication but are
open at deployment; PS.3.2 is fixed at release and open at deployment.
PW.4.1, PW.4.4, PW.7.2, PW.8.1, and PW.9.1 have observed controls; PW.7.1 and
PW.8.2 remain partial. RV.1.1 and RV.1.2 have scanners; RV.1.3 and RV.2.1
remain open; RV.3.1 was not verified in the baseline review.

## Safe closure state

Retain the current distinction: CRR is the sole activated item. Keep the
remaining source/GitOps/CI work unactivated until its explicit review and live
proof gates complete. Do not merge, deploy, publish a scanner image, import
state, migrate a backend/CMK, change repository plan/visibility, or represent
the mapping above as a compliance score from this evidence.

## Post-review resolution

The integration owner corrected the previously noted non-blocking CRR runbook
wording. It now records the dated approved activation/canary evidence and
retains gates for future changes; the independent observations above are
unchanged.
