# T-8: OPA-governed PR gates

## Outcome

Implement a required pull-request gate that collects Gitleaks, OSV-Scanner,
Semgrep, Zizmor, Checkov, formatting, and offline Terraform-validation
evidence; normalizes the required scanner evidence; evaluates the OPA decision;
and retains safe JSON/SARIF results.

## Delivery sequence

1. Confirm the evidence contracts and failure semantics, including the rule for
   redacting or withholding secret-bearing output.
2. Add isolated collector and adapter commands with deterministic fixture tests.
3. Add the pinned, least-privilege PR workflow that invokes only those commands
   and exposes OPA's result as the gate outcome.
4. Prove every required adversarial fixture blocks and the clean fixture passes.
5. Run the harness adapter checks, integrate, and commission the required
   clean-room debrief from a fresh agent.

## Boundaries

This task is repository-local CI work only. It does not deploy, publish, merge,
modify secrets, use AWS credentials, or contact production systems. Scanner
artifacts must be non-sensitive: a secret finding is represented by normalized
metadata rather than the secret or its raw finding payload.
