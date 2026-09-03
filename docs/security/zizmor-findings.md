# Zizmor findings register

This register records the Zizmor findings observed on 2026-09-03 while
introducing trusted scanner-evidence consumption. It is intentionally a
decision record, not a suppression list: every entry identifies whether the
code was changed or an exception is narrowly justified.

| Rule | Affected workflow(s) | Finding | Resolution |
| --- | --- | --- | --- |
| `template-injection` | `ci-security.yml`, `ci-terraform.yml`, `ci-release-integrity.yml`, `release.yml`, `scanner-image-release.yml`, `toolchain-image-release.yml`, `opa-pr-gate.yml` | `github.actor` was interpolated directly into a shell `run:` block during GHCR login. | Resolved by mapping `github.actor` and `github.token` to step-scoped environment variables, then expanding shell variables only. |
| `dangerous-triggers` | `opa-pr-gate.yml` | `workflow_run` can become privileged if it checks out or executes PR-controlled code. | Narrow documented exception. The workflow checks out policy/collector code only from the default branch, checks out PR content solely as read-only Terraform input, accepts SHA-bound scanner JSON, uses `permissions: read`, and runs Terraform without a network. Reassess if any write permission, secret, or PR-controlled executable is added. |

The evidence normalizer currently records Zizmor locations as `unknown` for
some scanner output variants. The source locations above were recovered from
the scanner's original `json-v1` output; improving location preservation is a
separate collector-quality follow-up.
