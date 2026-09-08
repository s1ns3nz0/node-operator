# Remaining security hardening status

Date: 2026-09-08. This is a follow-on to
`2026-09-08-cicd-optimization-redteam.md`; its DoD DEVELOP–DEPLOY, SSDF
PO/PS/PW/RV, and SP 800-204D 5.1.1–5.1.4 mappings remain the coverage baseline.
This report records observed changes, not a new blanket compliance score.

## Activated and verified

- Two primary S3 access-log buckets now replicate only their approved prefixes
  to their existing Tokyo terminal buckets. The reviewed Terraform plan created
  two roles, two exact policies, and two replication configurations with no
  updates, replacements, or deletes. Both retained zero-byte canaries reached
  `COMPLETED` and arrived as `REPLICA`/AES256 objects. A post-apply targeted plan
  had no managed changes.
- `CKV_AWS_144` now passes for the audit and release primary access-log buckets.
  The two Tokyo terminal destinations have exact, expiring `TERMINAL-REPLICA`
  proposals; validator-audit and Vault-snapshot regional DR remain separate
  accepted limitations.

## Implemented and reviewed, not activated

- Bootstrap-state reconciliation preserves legacy names, constrains exact
  same-account backend roles and S3 KMS use, and performs any future import only
  in a private copied module. It lists five observed import targets and does not
  invent an existing CMK. No import, CMK migration, backend migration, or apply
  was performed.
- Source DAST access uses fixed GET-only proxies. Nethermind exposes only a
  bounded TCP-connect P2P reachability result; JSON-RPC/Engine API remains
  inaccessible to DAST. This task does not change the live Nethermind API
  setting or the existing Engine path used by Prysm. The public-CA installer
  rejects private keys and canonicalizes X.509 certificates.
- GitOps DAST performs three fixed passive HTTP GETs and one separately labelled
  Nethermind P2P reachability check. It requires HTTP 200, verifies Vault CA and
  hostname, imports actual URL/response headers into an ephemeral bodyless HAR
  with `sendRequests=false`, and publishes only sanitized v2 evidence. The final
  nine-case fixture executes the production-rendered Job program with mocked
  transport; the initial duplicated behavioral model was rejected and removed.

## Scanner evidence and remaining gates

- Current Checkov 3.2.522 observation: 954 passed, 23 failed, 6 skipped, zero
  parse errors across 292 resources. These counts are not represented as clean.
  The six skips are exact proposed exceptions: four server-access-log SSE-S3
  service constraints and two terminal replica destinations. The remaining
  findings stay governed by their exact expiring dispositions.
- OSV Scanner v2.4 command ordering is corrected and independently reviewed in
  draft PR 128 at `59065ec`. Its five normal checks pass; trusted evidence still
  fails closed because the active immutable image embeds the predecessor
  command. Required sequence: reviewed merge, automatic main image build,
  digest verification, then a separate pin-promotion review. No waiver, merge,
  or image publication occurred.
- The CI review-refresh and release-proof implementation remains in draft PR
  127. Required-check activation awaits the corrected scanner image and live
  positive/negative exact-head evidence.
- Private GitOps branch protection is still unavailable under the current
  GitHub private-repository plan. No billing or visibility change was made.
- The corrected private DAST runner has not been executed in the private
  cluster, and exact pinned-image compatibility remains unproven. Source/GitOps
  promotion, public-CA installation, and a live passive run are still required.

No merge, release, scanner-image publication, bootstrap import, DAST deployment,
secret access, repository-rule change, or destructive cloud action is asserted.
