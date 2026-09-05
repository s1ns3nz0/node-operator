# Immutable release-input retry read

1. Capture the failed v0.1.2 evidence and identify the denied action.
2. Add `s3:GetObject` only for the release runner's immutable input prefix, pass its actual S3 VersionId to CodeBuild, and add regression assertions.
3. Apply the matching live inline-role policy, validate the Terraform and workflow contracts, then submit and merge the fix.
4. Create a new tag rather than retagging v0.1.2, run the protected release, and capture its outcome.
