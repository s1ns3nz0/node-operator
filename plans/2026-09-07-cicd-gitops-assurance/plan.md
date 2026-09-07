# Private DAST and GitOps CD assurance

1. Inspect current CI workflows, recent evidence-gate failures, Argo Application
   ownership, and the approved GitOps source boundary.
2. Repair the CI Evidence Gate so trusted policy evaluation is actionable for
   the PR subject and publishes an admissible decision.
3. Add a private-runner DAST contract that first proves Argo `Synced` and
   `Healthy`, then permits bounded non-mutating probes only through private
   connectivity.
4. Define the GitOps repository CD hand-off: immutable artifact digest,
   pre-sync policy evidence, post-sync Argo health, and DAST evidence must
   share one promotion subject.
5. Validate contracts locally; run any private runner or GitOps deployment
   action only after a distinct authorization.
