# Clean-room debrief: security evidence permissions

## Observed evidence

- The runner uses `set -euo pipefail`.
- The collector is now invoked as a foreground command, rather than through
  `exec`; `chmod -R a+rX "$evidence_directory"` follows it.
- The collector exit status is therefore checked by `set -e`: a non-zero
  status stops the runner before `chmod` is reached.
- The permission operation targets only `$evidence_directory`, the declared
  `EVIDENCE_DIRECTORY` input. No other path is passed to `chmod`.
- `bash -n .ci/scanners/run-security-scan.sh` and
  `git diff --check -- .ci/scanners/run-security-scan.sh` completed
  successfully during this review.
- The recorded workflow evidence says collection completed, but artifact
  upload failed with `EACCES` opening root-owned
  `.security-evidence/checkov.json`.

## Assessment

The changed control flow meets the requested error semantics: permissions are
relaxed only after the collector returns success, and collection failure
preserves the prior private permissions by exiting before the new command.
The recursive read/search permission change is scoped to the caller-declared
evidence tree. `a+rX` grants read access to files and traversal access only
where appropriate; it does not add write access.

This conclusion is limited to the runner's synchronous shell flow. The
available evidence does not independently demonstrate the next remote
workflow run or rule out collector-spawned background writers.
