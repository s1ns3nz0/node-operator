# Trusted workflow trigger disposition

## CI-REVIEW-REFRESH

`workflow.unsafe` / `dangerous-triggers` is accepted only for
`.github/workflows/ci-review-refresh-handler.yml` through 2026-10-03.

GitHub review events receive no repository permissions and execute no repository
code. Their only effect is to complete `CI Evidence Review Signal`. The
`workflow_run` handler executes from the protected default branch, validates the
signal workflow name, path, repository, event, conclusion, and unique pull
request, resolves the current PR head through the API, and can only rerun the
matching completed `CI Security` run. It cannot publish an approval check or
execute pull-request code directly.

The finding remains in scanner evidence and is suppressed only by the exact
rule/path pair above. Another workflow, rule, path, missing field, malformed or
expired date remains fail-closed. Before expiry, replace this exception with a
GitHub-supported event chain that preserves the same permission separation, or
renew it only after repeating the positive and replay/stale-head negative tests.
