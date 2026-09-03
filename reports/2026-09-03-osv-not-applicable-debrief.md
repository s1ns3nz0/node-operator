# Clean-room debrief: OSV not applicable

## Observed evidence

- The task bundle defines one exceptional condition: `osv-scanner` exits 128 and its stderr is exactly `No package sources found, --help for usage information.`
- The collector writes `status: "not_applicable"`, an empty vulnerability list, and the non-sensitive reason `no_supported_dependency_manifests` only for that condition.
- Every other nonzero OSV exit still stops collection before evidence is emitted; successful or exit-1 scans must also pass the existing JSON and shape checks.
- `scripts/ci/test-pr-evidence.sh` passed locally. Its expected malformed-report diagnostic was printed, then its new exit-128 fixture verified both collected and normalized evidence.
- `npm run harness:check` passed locally. `git diff --check` reported no whitespace errors.

## Inference

The exception is narrow and fail-closed: both the exit status and complete diagnostic must match, while malformed output and unrelated scanner failures remain rejecting conditions. The emitted result deliberately distinguishes an unsupported/dependency-free source layout from a clean vulnerability scan.

No external action, secret access, deployment, publication, or production access was observed.
