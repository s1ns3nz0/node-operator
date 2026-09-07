# Clean-room debrief: signer immutable-object version read

**Reviewer:** Terra clean-room reviewer  
**Reviewed commit:** `90d334ee600e79f6424debdaf9e46e2c8f13c414`  
**Review boundary:** the specified task bundle, this commit, and local static
checks only. No AWS, GitHub, production, secret, publication, deployment, or
other external-system access was performed.

## Observed evidence

- The task bundle records a CodeBuild `DOWNLOAD_SOURCE` failure for a selected
  `release-input/sha256/...` object version because the signer role lacked
  `s3:GetObjectVersion`.
- The reviewed commit adds a conditional Terraform IAM statement named
  `ReadImmutableSignerInputVersions`. Its sole action is `s3:GetObjectVersion`
  and its sole resource is `release-input/*` in the release-artifacts bucket.
- The commit adds a regression assertion for that statement, action, and exact
  resource scope; it also documents the intended version-read boundary.
- The supplied task evidence reports a live inline-policy update scoped to
  `release-input/*`. It supplies no policy document, command transcript, or
  runtime result.
- The task graph remains incomplete: implementation is `active`; validation,
  merge, and release are `pending`.
- Independent local static checks passed: `git show --check 90d334e`,
  `git diff --check 90d334e^ 90d334e`, Bash parsing of the changed regression
  script, and JSON parsing of the supplied evidence file.

## Inference and remaining boundary

The static change supports the inference that Terraform now expresses the
least-privilege permission needed to read the immutable release input version,
without adding object-version write or delete access. The committed regression
test should detect removal or broadening of that explicit statement.

This does not demonstrate live-IAM parity, Terraform plan/apply conformance,
CodeBuild source download success, or a successful new release tag. Those
acceptance items remain unproven and require separately authorised validation;
the bundle itself marks them pending.
