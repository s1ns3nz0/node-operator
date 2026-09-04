# Policy adapter runnable remediation: clean-room debrief

## Verdict

No blocking implementation finding. The change makes the intended local and CI
tool path explicit and fail-closed. Acceptance of a *completed local adapter
run* remains conditional on retaining its actual command output or exit-status
evidence; the task bundle records command names, not their results.

## Observed evidence

- Reviewed the task bundle and `044ff76..aa68d7d`, including all policy-tool,
  adapter, workflow, and raw-evidence-fixture changes. No cloud-facing command,
  deployment, secret operation, or other prohibited action is introduced.
- The bootstrap selects only `Darwin_arm64` and `Linux_x86_64`, downloads the
  pinned OPA 1.17.0, Conftest 0.69.0, and ShellCheck 0.10.0 artifacts, and
  verifies each downloaded artifact with an embedded SHA-256 before installing
  it. Unsupported platforms terminate with exit 64.
- `harness:verify` prepends `.ci-tools/bin`; it does not download tools. The
  explicit bootstrap command owns the download. CI Policy, CI Quality, and
  Policy Foundation bootstrap the same pinned tool set and use `GITHUB_PATH`
  for following steps, so their relevant adapter commands resolve the same
  binaries rather than the runner defaults.
- The new `incomplete/osv.json` has a syntactically valid collector envelope
  but an array-valued `result`. The normalizer requires an object and the test
  asserts the exact `invalid osv collector envelope` failure. This preserves
  fail-closed behavior and tests it without a missing-file false positive.
- The two ShellCheck suppressions are scoped to SC2016 and explain that their
  Terraform/workflow fragments are deliberately literal.
- Independently re-ran without downloads: `scripts/ci/test-policy-tool-bootstrap-contract.sh`,
  `scripts/ci/test-normalizer.sh`, `npm run harness:check`, and
  `git diff --check 044ff76..HEAD`; all exited 0.

## Inference and remaining risks

- The bundled `evidence.json` names `npm run harness:bootstrap-policy-tools`
  and `npm run harness:verify`, but contains no status, timestamp, or captured
  non-sensitive result. I did not rerun them because that would install and
  download tools, outside this review scope. Preserve that output before
  representing the full local adapter run as independently evidenced.
- `test-policy-tool-bootstrap-contract.sh` is static text matching. It confirms
  declared pins/checksum logic, not that the checksum values match upstream
  releases or that archive extraction works. The explicit bootstrap run is the
  necessary runtime corroboration.
- The platform matrix intentionally excludes Intel macOS and Linux arm64. It
  fails closed with a clear error, but those developers/runners need a reviewed
  pinned extension before they can run the adapter.
- Bootstrap installation is per-artifact rather than transactional; a later
  download failure can leave already-verified earlier binaries in the selected
  ignored directory. Since verification only runs after an explicit bootstrap,
  this does not silently fall back to system tools, but a clean destination is
  preferable when recovering from a failed bootstrap.
