# Independent Terra review — credential boundary and verify mode

## Review contract

- Reviewer: independent Terra reviewer
- Requested tier/model: `terra` / `gpt-5.6-terra`
- Fallback: none
- Scope: current local diff for the `ops-access` Terraform credential boundary
  and `verify` mode only. No implementation files were changed and AWS was not
  accessed.
- Initial result: **BLOCKED — two release-blocking findings.**
- Re-review result: **PASS — both blockers resolved in the current diff.**

## Blocking findings

### B1 — “Separated” mode permits a single backend/provider identity

`scripts/release/node-operator-ops-access.sh` only requires that all four
separation arguments be present (lines 24–31), then independently compares
each resolved principal with the caller-supplied expected ARN (lines 114–124).
It does not require different profile names, different expected ARNs, or
different resolved IAM principals. A caller can therefore provide the same
named profile twice and the same expected role or user ARN twice; both STS
checks pass, `credential_boundary=true`, the backend receives that profile,
and Terraform also runs under that same profile. This is a compatibility path
labelled as separation rather than actual backend/provider credential
separation.

This defeats the stated boundary: a state-capable principal can also be used
for provider refresh/apply whenever it has those permissions. The focused test
only exercises two different mock profiles/principals and has no same-profile
or same-principal rejection case.

Required remediation: after canonicalization, reject equal backend and provider
principals (and preferably equal profile identifiers as an early clear error),
and add offline tests for identical profile/ARN and two distinct profiles that
resolve to the same IAM role. Keep ambient mode explicitly separate for the
approved legacy ceremony.

### B2 — `verify` can mutate the bundle’s dependency lock file

`verify` sets `TF_DATA_DIR` only for Terraform’s data directory (lines
240–247), but subsequently invokes `terraform init` without
`-lockfile=readonly` (line 249). Terraform’s dependency lock file is
`infra/ops-access/.terraform.lock.hcl`, which is in the module/configuration
directory rather than `TF_DATA_DIR`; it is present and tracked in this
worktree. Consequently `init` may create or update that lock file when provider
selection/platform hashes require it. That contradicts the documentation claim
that verify initialization cannot rewrite active module metadata and makes a
nominally read-only verification capable of altering the release bundle.

Required remediation: make verify initialization use the read-only lockfile
mode (and fail closed if the locked provider set cannot be used), then extend
the focused test to assert the init arguments and no module lock-file mutation.

## Non-blocking observations

- Backend selection is otherwise correctly supplied after the backend config as
  `-backend-config=profile=$backend_profile`, while Terraform’s provider
  process receives the provider `AWS_PROFILE`; the module itself has no AWS
  provider `profile` override.
- The STS normalization retains IAM user ARNs and converts an assumed-role ARN
  to an IAM role ARN. It deliberately fails closed for IAM role paths, because
  the STS assumed-role ARN exposes only the role name. The focused test covers
  the assumed-role case but should also add a direct IAM-user success fixture.
- Verify uses `plan -lock=false -detailed-exitcode`, accepts only the exact
  nine-resource retained-host guard shape, and additionally requires every
  managed action to be `no-op` with a zero plan exit code. `--allow-create` is
  rejected and the test exercises that rejection.
- The private-plan path validation rejects a supplied symlink and requires a
  non-group/non-world-accessible immediate parent. Verify checks derived JSON
  and data-directory nonexistence before use. The cleanup trap removes only
  the derived private paths, but its `rm -rf` cleanup should remain limited to
  paths created after the existing private-path checks.
- No secrets, raw state, tokens, or credential values are added to the diff;
  documentation examples use identifier placeholders only. The wrapper does
  not print STS JSON or Terraform plan JSON during successful verification.

## Checks run

All commands were local and did not contact AWS.

| Check | Result |
| --- | --- |
| `bash -n` for changed release/test scripts | PASS |
| `npm run test:ops-access-credential-boundary` | PASS |
| `bash scripts/ci/test-ops-access-retention-release.sh` | PASS |
| `npm run harness:check` | PASS (92 task graphs) |
| `npm run harness:verify` | PASS (all policy adapters; expected insecure fixtures emit their asserted Conftest findings) |
| `scripts/ci/test-script-quality.sh` | PASS |
| `git diff --check` | PASS |

## Integration gate

Do not claim the new path as credential separation or read-only verification
until B1 and B2 are addressed and the focused tests cover the rejected cases.

## Re-review and resolution evidence

The integration owner supplied a revised current diff for independent
re-review. This reviewer again made no implementation edits and did not access
AWS.

### B1 resolved

The wrapper now rejects equal backend/provider profile names and equal expected
principal ARNs before any STS or Terraform invocation (current lines 32–36).
Each profile is still independently normalized and compared to its exact
expected ARN (lines 116–126). Therefore, accepted inputs have both distinct
profile identifiers and distinct resolved IAM principals: if both profiles
resolved to one principal, that principal could not equal two distinct expected
ARNs. Ambient mode remains the intentionally separate compatibility path.

`test-ops-access-credential-boundary.sh` now proves that identical profile and
principal arguments fail. The existing distinct-profile happy path continues to
prove backend `profile=` forwarding and provider `AWS_PROFILE` scoping. A
separate-profile/same-resolved-principal fixture would improve diagnostic test
coverage, but the exact-match invariant already rejects it and it is not a
release blocker.

### B2 resolved

All wrapper operations now invoke Terraform initialization with
`-lockfile=readonly` (current line 254). Combined with verify mode's private
`TF_DATA_DIR`, this prevents `init` from updating the tracked module
`.terraform.lock.hcl` and fails closed if the dependency selection is not
already admissible. Verify retains `-lock=false`, detailed exit-code handling,
the exact retained-host guard, no-op enforcement, and cleanup of its temporary
plan, JSON, and Terraform-data directory.

The retention-release test exercises successful verify cleanup and rejection of
`--allow-create`. It does not explicitly assert the mocked init argument; that
would be useful defense-in-depth coverage, but the current implementation is
unambiguous and the prior lockfile-mutation blocker is resolved.

### Re-review checks

All commands were local and did not contact AWS.

| Check | Re-review result |
| --- | --- |
| `bash -n` for changed release/test scripts | PASS |
| `npm run test:ops-access-credential-boundary` | PASS |
| `bash scripts/ci/test-ops-access-retention-release.sh` | PASS |
| `scripts/ci/test-script-quality.sh` | PASS |
| `npm run harness:check` | PASS (92 task graphs) |
| `npm run harness:verify` | PASS (all adapters; insecure-fixture Conftest output is expected by the adapter) |
| `git diff --check` | PASS |

Final independent-review disposition: **PASS.**
