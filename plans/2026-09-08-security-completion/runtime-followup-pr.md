## Scope

Stacked follow-up to #127. Keep the parent PR's reviewed head unchanged.

- Preserve signer certificate verification while supplying the existing allowed HTTP Host.
- Add exactly four SG-reference TCP rules for cross-pool Prysm health, Nethermind reachability and bidirectional Vault HA.
- Run both focused regression suites in the required quality job.

## Verification

- Independent six-file review approved; signer and cross-pool contract suites passed.
- ShellCheck, shell syntax, Terraform format, diff check and harness validation passed.
- Optional Kyverno CLI fixture suite was explicitly skipped locally because the CLI was unavailable; no engine-validation claim is made here.
- Reviewed runtime changes are already applied. The four-rule readback and targeted no-drift check passed.
- Actual private DAST reached all four fixed targets with HTTP 200 and verified Vault TLS, but **still failed on one passive alert**. This PR does not waive the alert or claim DAST completion.

## Integration

Draft until parent #127 lands. Retarget to main and rerun required checks before normal merge. No admin bypass, broader ingress, certificate relaxation, signing request or full-baseline apply.
