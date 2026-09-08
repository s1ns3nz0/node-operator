# Integration completion

The ops-access wrapper now has a fail-closed separated credential mode. It
requires distinct named profiles and distinct exact IAM principals, gives the
S3 backend its explicit profile, gives the AWS provider a separate profile,
rejects exported AWS keys/tokens, and removes conflicting credential-source
environment variables. Ambient mode remains only for existing explicitly
approved single-identity ceremonies.

The new `verify` operation is lock-free and refresh-backed. It uses an isolated
Terraform data directory, read-only dependency lock file, the retained-host
guard, and an all-managed-resources-no-op gate. It removes the temporary plan,
JSON, and Terraform metadata on every exit and never creates an apply artifact.

The final live read used `NodeOperatorTerraformApply` only for the canonical S3
backend and the existing `jsyang` management user only for provider reads. It
returned nine no-ops. The S3 object version and tracked provider lock file were
unchanged. This resolves read verification without adding `iam:GetRole` to the
backend role. It does not create a least-privilege provider automation role,
reduce the existing user's permissions, or authorize unattended apply.

The validator roadmap supersedes stale graph labels. Deposit and custody are
reported as already performed, but T13 remains in progress because public
evidence correlation is missing; another deposit is expressly excluded. T3
and T4 completion relies on timestamped 2026-09-07 lifecycle evidence and was
not reverified in this turn. The current private beacon is synced but
returns 404 for the queried key; no validator client is deployed. UC-5 revoke
and restore passed only in its bounded form. Observer correctness, public
receipt/Event correlation, activation, first duty, post-recovery duty, and
archive/reindex failure exercises remain explicitly separated.

Focused credential and retained-host tests, ShellCheck, `harness:check`, and
`git diff --check` passed. Independent Terra review initially blocked actual
identity separation and lock-file immutability; both were fixed and re-review
passed. Requested model tiers were used without fallback. No IAM policy, secret,
state, workload, validator, Git remote, or server-side SSM mutation was made by
the integration owner.
