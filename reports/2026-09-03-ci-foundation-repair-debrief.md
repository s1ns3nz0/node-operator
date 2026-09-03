# Clean-room debrief: CI foundation repair

## Observed evidence

- Before the repair, `test-normalizer.sh` expected an empty
  `policy.exceptions` array even though `normalize-evidence.sh` intentionally
  embeds the canonical registry. The current registry contains nine approved,
  unexpired Checkov exceptions.
- Commit `813a42de088d457f641b8608cfc6394e6ef27794` changes the normalizer
  assertion to require exact equality between emitted exceptions and
  `policy/data/exceptions.json`. It retains the clean Gitleaks finding,
  formatting, Terraform-status, redaction, and incomplete-fixture assertions.
- That commit changes SC2016-triggering literal patterns only in seven
  CodeBuild, ECR, and Vault contract-test scripts. The expected text is now
  represented with escaped double-quoted literals; no ShellCheck suppression
  was added.
- The first remote repair attempt found an additional ShellCheck 0.9 SC2015
  diagnostic in `validate-terraform-offline.sh`. Commit
  `ac1317e2ddec039644e4fd6f1b5095ac091ea69b` replaces its two-bound argument
  guard with an explicit `if` that rejects fewer than two or more than three
  arguments and retains the same usage failure exit path.
- Recorded local evidence states that the normalizer and all seven affected
  contract tests passed; `bash -n` over `scripts/ci` passed; Ubuntu 24.04
  ShellCheck 0.9 passed through `test-script-quality.sh`; and both
  `npm run harness:check` and `git diff --check` passed.
- Recorded remote follow-up evidence states that commit
  `ac1317e2ddec039644e4fd6f1b5095ac091ea69b` passed CI Quality run
  `33745697580` and Policy Foundation run `33745697518`.
- The task evidence records no change to workflow permissions, policy
  exceptions, cloud or Vault state, secrets, or production state.

## Assessment

The observed changes do not weaken policy enforcement. The normalizer test is
strictly stronger for the intended behavior: it now verifies the complete
canonical exception registry instead of requiring an empty list, while its
clean-evidence and secret-redaction checks remain. This assessment relies on
the recorded fact that the registry already holds nine approved, unexpired
exceptions; the repair itself did not alter that registry.

The ShellCheck changes preserve the literal strings that contract tests search
for and add no blanket suppression. The follow-up argument guard is
semantically equivalent for accepted and rejected argument counts, inferred
from its explicit lower- and upper-bound checks and unchanged exit behavior.
Together with the successful local and remote gates, the available evidence
supports accepting the repair as a CI-quality and test-contract correction,
not a relaxation of policy controls.

The task is not yet administratively complete: `graph.json` still marks T3
as `in_progress`, and `evidence.json` remains `in_progress`. Final integration
must update the evidence graph status before closing the task.
