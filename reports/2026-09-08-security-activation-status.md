# Security activation status

Scope: follow-up to the DevSecOps remediation review (DoD DEVELOP through
DEPLOY, SSDF PO/PS/PW/RV, and SP 800-204D sections 5.1.1–5.1.4). This is an
implementation/activation update, not a new claim of framework compliance.

## Observed AWS changes

Account 106760547719, Seoul region. Caller identity verified before mutation.
Existing baseline state was confirmed populated at
`node-operator/t2/terraform.tfstate`; older empty-state reports are stale.
The independent bootstrap/foundation/ops state locations remain unverified.

- Validator workload log retention increased from 90 to 365 days in place;
  existing KMS encryption retained. AWS readback confirms 365 days.
- Saved stage-1 Terraform plan applied: 6 additions, 1 update, 0 deletions.
  Two audit/snapshot bucket access-log configurations and EventBridge
  notifications are enabled, with the existing dedicated access-log bucket.
- Vault snapshot lifecycle aborts only incomplete multipart uploads after
  seven days. There were zero multipart uploads before activation. It has no
  completed-object or version expiration. Existing Object Lock remains enabled
  (snapshot: 90-day GOVERNANCE; validator audit: two-year GOVERNANCE).
- Dedicated Firehose buffer CMK created; enabled rotation independently read
  back. Stage 2 added only the exact-key producer IAM policy; both KMS actions
  were allowed in IAM simulation before stage 3 changed only stream SSE.
- Firehose readback at 04:18:16 UTC: ACTIVE, encryption ENABLED,
  CUSTOMER_MANAGED_CMK, exact approved key. Post-activation metrics at 04:20 UTC
  show S3 delivery success and 277 delivered records; four KMS error metrics
  remain zero in the observed window. This is transport-health evidence, not
  proof of every validator activity or permanent absence of failures.
- Replanning all scoped Firehose/S3/log-retention targets returned exit 0 and
  no managed changes. This is not a full-stack drift-free claim.
- Terraform lock table PITR changed from DISABLED to ENABLED in place, with
  35-day recovery period read back. Earlier recovery history is not retroactive.

The saved plan/state artifacts stay in a mode-0700 temporary directory, outside
Git. Evidence below contains only hashes, addresses, actions, and public settings.

## IaC ordering correction

Producer KMS permissions moved into an independent exact-key inline policy;
Firehose now explicitly depends on that policy. This avoids the former
dependency that enabled SSE before the producer's KMS policy was installed.
Terraform validation, formatting and a focused regression test pass. Independent
Terra review found no blocking issue or new Checkov finding from this split.

AWS requires the producer IAM policy and CMK policy to allow GenerateDataKey
and Decrypt for customer-managed Firehose encryption. See
[Firehose data protection](https://docs.aws.amazon.com/firehose/latest/dev/encryption.html).
Enabling is asynchronous; configuration success is not proof of delivered logs.

## Remaining controls, not represented as passed

- The actual newly pinned scanner image detected a synthetic token-shaped
  marker in a prior Git commit after it was removed from HEAD. Full-history
  scan exited 1 with a redacted finding; latest-commit-only comparison exited 0.
  This was an isolated, network-disabled local test, never pushed to GitHub;
  it does not replace hosted positive/negative gate proof.
- CI approval-refresh now separates an unprivileged review signal from a
  trusted default-branch handler. Release-check verification binds publisher
  run, exact subject, and downloaded passing evidence; later changes-requested
  reviews invalidate an earlier approval. Regression validation is local;
  hosted activation remains unproven.
- The new trusted handler's reviewed-intent Zizmor suppression is still subject
  to the existing untrusted-suppression guard. No bypass or exception has been
  added to promote it. A reviewed promotion path must be decided before merge.
- Live positive/negative exact-head gate proof and required-check activation.
- GitOps private-repository protection remains externally blocked by GitHub's
  plan restriction; no billing or visibility change is authorized.
- Private CD/DAST live evidence and end-to-end log delivery validation.
- Bootstrap state KMS/logging and separate foundation/ops resources need state
  ownership reconstruction before any apply. Do not create a second live stack.
- Legacy ECR encryption replacement/migration remains separately gated.
- Raw Checkov 3.2.522 currently reports 26 failed and 8 skipped checks, not zero
  skipped. All eight skipped check/resource pairs are absent from the central
  exception register: CKV_AWS_144 and CKV_AWS_145 for audit_access_logs,
  audit_replica_access_logs, release_artifacts_access_logs, and
  release_artifacts_replica_access_logs. The trusted collector treats these as
  failures. No exceptions were added or controls weakened in this task.

Direct S3 server-access-log destinations retain SSE-S3 as required by
[AWS logging prerequisites](https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html).
Changing those destinations to SSE-KMS solely to satisfy a scanner would break
  the documented delivery configuration.

## Safe next sequence

1. Complete independent CI review and preserve this change as a draft, without
   merging or changing required checks.
2. Resolve the eight unregistered inline skips explicitly: implement supported
   actual controls where possible; use a separately approved design decision
   for service-incompatible rules. Do not turn scan failures into hidden skips.
3. Review and authorize the new handler's trusted promotion, then obtain live
   exact-head positive/negative and post-review-refresh proof.
4. Add the required evidence check only after those proofs; resolve GitOps plan
   protection externally before private-CD promotion.
5. Reconstruct/import separately owned bootstrap/foundation/ops state before
   planning remaining live drift. Preserve existing bucket names, endpoints,
   ECR images and SSM access; replacements require a separate reviewed plan.
