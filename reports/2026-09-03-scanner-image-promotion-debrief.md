# Clean-room debrief — scanner image promotion

## Observed evidence

- `main` and `origin/main` both resolve to
  `cf94931f02cb54503a515ff12f4c445180ad4493` at final review time.
- `CI Security` pins `security-scanners` by the exact digest
  `sha256:fa610d21080bc46560e0a405e310e1144dacfebfd5f02120cb7985adfb699bfa`.
  CI Security run `33719414877` succeeded with that promoted reference.
- The Dockerfile accepts `SCANNER_INPUT_SHA` and persists it as
  `io.node-operator.scanner-input-sha`.
- The release script hashes the Dockerfile, its `.dockerignore`, and every
  repository file copied by the Dockerfile: the runner plus the two collectors
  and shared shell library. Both the release script and its fixture reduce each
  per-file checksum to its checksum field before calculating the aggregate;
  their result therefore does not depend on absolute versus relative filenames.
- It pulls `:main`, reads that label, and skips only when the label is nonempty
  and equal to the calculated hash. Missing labels, pull/inspect failures, and
  different values proceed to build and push both the commit and `:main` tags.
- `test-scanner-image-release.sh` supplies a matching label and makes every
  mocked Docker operation other than pull/inspect fail. The test passed, so the
  matching-input path did not build or push. Manual Scanner Image Release run
  `33719439781` also logged `scanner image inputs are unchanged; skipping build
  and push`.
- The image-release workflow runs for every hashed repository input, and CI
  Quality executes the deduplication fixture. An earlier CI Quality failure was
  repaired with the needed `SC2016` suppression; the latest full quality and
  security gates passed.

## Inference and assessment

The observed branch makes source-identical scanner-image releases idempotent:
once `:main` carries the calculated label, a later matching workflow run exits
before any Docker build or push. Digest promotion is immutable because CI uses
an `@sha256:` reference rather than a mutable tag; the recorded release result
is the evidence linking the selected digest to publication.

The content hash covers all local Docker build-context inputs used by this
Dockerfile. It does not independently fingerprint the resolved `ubuntu:24.04`
base-image content or the bytes served by external download URLs. Thus a change
to either upstream resource without a repository change will not by itself
cause a rebuild; this is a limitation of source-change deduplication, not a
false skip for the tracked inputs.

No external action, secret access, deployment, publication, or production
access was performed by this reviewer.
