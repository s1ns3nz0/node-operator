# Trusted workflow trigger disposition

## CI-EVIDENCE-GATE

`workflow.unsafe` / `dangerous-triggers` is accepted only for
`.github/workflows/opa-pr-gate.yml` through 2026-10-03. This is not a false-positive
claim: the trigger still starts a privileged follow-on workflow. The diagnostic
after removing its old inline suppression reports High severity and Medium
confidence. The finding must remain visible in scanner evidence.

The resolver and control-plane scripts come from the default-branch workflow
SHA, not the pull-request checkout. The resolver validates the upstream CI
Security workflow name/path/repository/event, exactly one PR, the 40-hex subject
and its equality to the API current PR head. Checkouts do not persist credentials.
PR/base source is passed as read-only input to scanners. Scanner/Terraform
containers receive no GitHub token; Terraform also has no network. Only trusted
host steps receive scoped tokens and publish the exact-head evidence check.

Residual risk remains: scanner parsing has network access, checks-write jobs
process attacker-derived evidence, and this path/rule disposition is not a
cryptographic binding to the current workflow body. Later edits at this path
therefore require fresh trust-boundary review even before expiry. The required
exact-head sensitive-path approval and existing boundary regression checks
remain enabled; temporarily disabled CODEOWNER/minimum-review branch settings
are not claimed as active protection. Wrong paths/checks/rules and expired
entries fail closed. Re-review or remove this disposition before expiry.

This policy-only prerequisite does not remove the legacy inline comment itself.
PR135 must remove it after this policy is trusted on main, without weakening
the collector rule that rejects untrusted inline suppressions. Scanner promotion
and the SSM runtime/state changes remain separate from this disposition.

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
