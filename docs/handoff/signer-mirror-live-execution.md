# Private signer mirror live execution

Date: 2026-09-05

The private signer-image mirror foundation was exercised under explicit user
authorization. The destination is an immutable, KMS-encrypted ECR repository;
its lifecycle policy retains the newest `approved-` digest tag only.

The successful workflow run was `33894047539`. It copied the reviewed GHCR
signer source into the private ECR repository and verified the resulting image
digest with ECR. The exact digest is recorded in the task evidence bundle.

During the first successful push attempt, the workflow's later `DescribeImages`
call lacked permission and its temporary OIDC credentials were not masked in
the GitHub log. The affected run was deleted. The follow-up workflow masks all
temporary credentials before exporting them and the role now has only the
required additional `ecr:DescribeImages` permission. No long-lived credential
was used or stored.

After the final verification, the `ecr-signer-mirror` required-reviewers rule,
self-review prevention, and main's one-approval rule were restored.
