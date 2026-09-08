# Zizmor findings register

This register records the Zizmor findings observed on 2026-09-03 while
introducing trusted scanner-evidence consumption. It is intentionally a
decision record, not a suppression list: every entry identifies whether the
code was changed or an exception is narrowly justified.

| Rule | Affected workflow(s) | Finding | Resolution |
| --- | --- | --- | --- |
| `template-injection` | `ci-security.yml`, `ci-terraform.yml`, `ci-release-integrity.yml`, `release.yml`, `scanner-image-release.yml`, `toolchain-image-release.yml`, `opa-pr-gate.yml` | `github.actor` was interpolated directly into a shell `run:` block during GHCR login. | Resolved by mapping `github.actor` and `github.token` to step-scoped environment variables, then expanding shell variables only. |
| `dangerous-triggers` | `opa-pr-gate.yml` | `workflow_run` can become privileged if it checks out or executes PR-controlled code. | Narrow documented exception. The workflow resolves its control-plane code from the exact default-branch workflow SHA, verifies the upstream workflow identity and current PR head through the API, checks out PR content only as read-only input, and runs Terraform without a network. Only the two publisher jobs receive job-scoped `checks: write`; no PR-controlled executable receives that token. |

The evidence collector accepts both current `given_path` and legacy
`verbatim_path` Zizmor locations and normalizes them to repository-relative
workflow paths. This prevents distinct findings from collapsing into the same
`unknown` baseline identity.
