# Exact candidate publication

1. Verify caller, immutable/KMS repositories, retained local evidence and OCI descriptors.
2. Independently review bounded publisher before execution.
3. Publish exactly two reviewed local images. Reject conflicting tags; equal-digest retries only verify and rescan.
4. Pull immutable registry subjects, verify identities and binary hashes, scan with pinned Docker-hosted tools and retain raw summaries.
5. Review new exact candidate/applicability bindings and evaluate new evidence. No raw finding suppression.
6. Preserve evidence and prepare PR for hosted verification of the new digests; no merge or live rollout in this task.
