# Require the trusted decision before positive-flow completion

Source PR127 and PR131 were externally merged within seconds of actual review,
before trusted review refresh completed. Both retained their prior failed
custom check. Waiting to enforce until positive-flow proof has twice allowed
the exact unprotected race the task is meant to prevent.

Primary Sol-role review approved enabling the app-pinned evidence check now
under the existing task-level security-enforcement authorization. Actual
missing-review failure and deliberate scanner-block failure are already
proven on exact heads. Accept temporary merge blockage while positive review
refresh is proved; never waive the check to get a merge through.

Change only the required-status-check list: add `CI Evidence Decision`, GitHub
App ID 15368. Preserve strict mode, quality/scanners, administrator enforcement,
and all review settings. Fresh-read and abort on unexpected current protection;
read back the exact union and verify the unrelated protection fields match.

Requirement 3 remains incomplete until a real current-head approval triggers
refresh and a successful exact-head decision, and GitOps protection is enforced.
