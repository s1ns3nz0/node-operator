# Clean-room debrief: Vault delivery remediation

## Disposition

Conditionally accepted at the repository-contract level. The reviewed diff
binds the Vault chart to an allowlisted archive and SHA-256, pins the bootstrap
toolchain packages, preserves digest-addressed private runtime images, adds the
required read-only ECR manifest probe, and proves an offline revoke plan omits
the temporary EKS cluster-admin association while retaining the private
executor. No deployment, secret operation, or Vault initialization was
observed in the supplied bundle or the reviewed diff.

The supplied non-sensitive evidence records successful approved-artifact
mirrors and targeted ECR/IAM changes. This is reported evidence, not
independently verified external state.

## Independent checks

Passed: `npm run harness:check`; toolchain, Vault GitOps, chart-mirror,
revocation, and OCI-mirror contract checks; offline revoke-plan check (run via
`bash`); `terraform fmt -check -recursive infra/terraform`; and `git diff
--check`.

`npm run harness:verify` did not complete in this environment: `opa`,
`conftest`, and `shellcheck` are unavailable, and the required incomplete-OSV
fixture is absent. Also, `test-vault-bootstrap-revoke-plan.sh` is not marked
executable, so invoking its path directly fails; it passes when run with
`bash`.

## Remaining gate

Before any live Vault/EKS prepare or deployment, obtain a separately reviewed
and approved operational plan. That plan must include a runnable policy-adapter
evidence set and retain the explicit post-bootstrap cluster-admin revoke step.
