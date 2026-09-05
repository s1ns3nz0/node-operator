# Clean-room debrief: immutable release-input retry read

Reviewed task bundle `2026-09-05-release-retry-read`, commit
`71659390ab862332e7487950b97a50eb68272392`, and the recorded/local structural
checks only. No AWS, GitHub, secrets, or production systems were accessed.

## Observed evidence

- The bundle records that GitHub Actions run `33936137823`, attempt 2, received
  `PreconditionFailed` from `PutObject`, then a `HeadObject 403` while retrieving
  the existing immutable input.
- Commit `7165939` adds runner `s3:GetObject` limited to
  `release-input/sha256/*`; it does not add delete permission in the Terraform
  policy. The recorded IAM simulation reports `GetObject` allowed and
  `DeleteObject` implicitly denied.
- The release workflow reads the uploaded object's `VersionId`, rejects an empty
  or `None` result, and passes that value as CodeBuild's `--source-version` with
  the existing source-location override.
- The commit adds structural assertions for the scoped runner read permission,
  the VersionId lookup, and the VersionId source-version handoff. The task
  evidence records passing `terraform fmt -check`, the CodeBuild activation and
  Vault-release contract scripts, and `npm run harness:check`. `git show --check`
  reported no whitespace errors.

## Inference

The change is consistent with resolving the recorded retry failure: a runner
that encounters the intentional no-overwrite precondition can now read and
compare the existing SHA-addressed input, and CodeBuild is directed to the
specific stored object version rather than the Git SHA. The added read scope is
limited to the immutable-input prefix in the Terraform source.

## Remaining evidence gap

The task graph and contract remain active, with validation/release pending. The
reviewed material does not contain evidence of live IAM-policy application,
creation of a new tag, or a successful protected-release run. Therefore those
acceptance items are not verified by this debrief; the recorded checks are
structural/local plus a recorded IAM simulation result.
