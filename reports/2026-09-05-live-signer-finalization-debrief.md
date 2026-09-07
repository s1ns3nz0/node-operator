# Clean-room debrief: live signer finalization

Task: `2026-09-05-live-signer-finalization`  
Reviewer: independent clean-room reviewer  
Disposition: **the task bundle records completion, but live AWS/GitHub results and the credential-exposure remediation cannot be independently attested from the supplied local evidence.**

## Scope

Read-only review covered the finalization task bundle, the live-execution
handoff, relevant changes through `origin/main`, and locally accessible
validation claims. No AWS, ECR, GitHub environment, Actions-log, workflow-run,
or secret-manager access was used. Therefore statements about live operations
below are attributed to the evidence/handoff unless otherwise noted.

## Observed evidence

- The task contract records explicit authority for the AWS changes, GitHub
  protection bypass/restoration, dispatch, image publication, and merge. Its
  graph now marks all four steps complete.
- `evidence.json` records passing `harness:check`, ECR mirror contract,
  script-quality, and whitespace checks; it records successful mirror run
  `33894047539` and private ECR digest
  `sha256:0cfcb3413265e711404cd99168d3327d5eb75b438cdf8b974fa5258f56bea839`.
  These are recorded claims, not raw command output or API responses.
- The relevant `origin/main` diffs add an immutable-tag lifecycle policy that
  retains one `approved-` image, add the exact GitHub `repository` claim plus
  environment-only subject alternatives to the OIDC trust contract, grant only
  the additional `ecr:DescribeImages` read action needed for verification, and
  require the new controls in the structural contract test.
- The final workflow change masks all three STS credential values before
  writing them to `GITHUB_ENV`; this closes the code path that could print the
  values in a later step.

## Security and evidence limitations

The handoff and evidence explicitly record that failed run `33893649730`
exposed temporary STS credentials in an Actions log, and that the run was
deleted. This is a real credential-exposure incident even though the evidence
file contains no secret value. The stated 900-second session limit and
single-repository ECR push boundary reduce impact, but deletion of a log does
not prove no observer retained its contents, revoke the issued session, or
prove the role boundary at the time of use. The available material contains no
timestamps, CloudTrail/IAM access analysis, or GitHub log/environment audit
with which to independently close that incident.

Likewise, the evidence says required reviewers, self-review prevention, and
main's one-approval rule were restored. The clean-room review cannot verify
their current GitHub configuration. The structural tests establish intended
source, destination, masking, and Terraform fragments; they do not prove the
applied IAM policy, environment settings, image manifest parity, or retention
execution. The documented final ECR digest is not accompanied by the source
digest or raw `DescribeImages` output, so parity is inferred from the recorded
workflow behavior rather than independently demonstrated.

## Follow-up required for operational closure

Retain non-secret audit evidence outside this report showing: the affected STS
session expiry and actions, deletion/review of the failed log, the current OIDC
trust and single-repository IAM policy, restored environment/branch rules, and
source-to-destination digest comparison for run `33894047539`. No secret,
token, or raw credential should be copied into the task bundle.

Within the reviewed source, the remediation is directionally sound: OIDC is
bound to the exact repository plus protected environment, credentials are
masked before export, and verification adds only `ecr:DescribeImages`. This
conclusion is an inference from the reviewed diff, not confirmation of live
cloud state.
