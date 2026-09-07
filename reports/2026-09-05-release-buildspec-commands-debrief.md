# Clean-room debrief: release buildspec commands

## Reviewed inputs

- Task bundle at commit `d38a58e79d9b54406976baebaec31b33ffe0c72c`.
- Commit diff for `d38a58e` (`fix: correct release signer command quoting`).
- Recorded checks in the task evidence, plus an independent YAML-array parse of the committed buildspec.

## Observed

- The commit removes backslash-escaped double quotes from the two shell command strings that embed `awk` and `jq` programs in `deploy/vault/buildspec-release-sign.yml`.
- The regression contract now requires the unescaped `awk` predicate and fails if any literal `\\\"` remains in the buildspec.
- The evidence records a CodeBuild failure in which Bash started successfully and `awk` rejected the literal escaped quotes.
- Recorded checks report successful Ruby YAML parsing, `awk` and `jq` fixtures, signer/release contract tests, and `npm run harness:check`. The independent review also confirmed that the committed YAML exposes `phases.build.commands` as an array.
- The bundle's contract and graph remain `active`; the next graph node is protected-release validation and is pending.

## Inference

- Removing the YAML-irrelevant escapes should allow the intended shell-embedded `awk` and `jq` programs to reach their parsers with normal quote characters.
- The added negative assertion reduces the chance that the same escaping defect is reintroduced.
- This evidence supports the source-level correction and local/static validation only. It does not establish that a new protected release executed or that private signing completed; that remains pending in the task graph.

## Scope and safety

No AWS, GitHub, secret, production, deployment, publishing, merge, or tag action was accessed or performed during this debrief. Unrelated worktree changes were not modified.
