# One finalized duty for the authorized local E2E run

Status: accepted 2026-09-15. Authority: explicit user approval.

Scope: AWS account `106760547719`, Region `ap-northeast-2`, deployment
`node-op-2609140157`, validator set `hoodi-001`. This is a threshold decision,
not a standalone operational runbook; execute only with the linked specification
and the task's separately approved external-action contract.

For the currently authorized local Hoodi E2E run, completion requires one
post-activation assigned duty whose canonical inclusion is finalized and
independently confirmed by the private Beacon and public Beacon source. Invoke
the local runner with `--required-finalized-epochs 1`; the observer, runner,
and monitoring result validators must use that explicit threshold. No proof
predicate is relaxed. The existing [completion and evidence requirements](../product-specs/installer-e2e-duty.md#completion-and-evidence)
remain the canonical definition of the deployment identity, activation bound,
Beacon evidence, archive delivery, Vault audit, checkpoint, and PASS evidence.

The distributable installer retains its general compatibility default of three
consecutive finalized duties. This decision only authorizes the local runner's
explicit one-duty option for this run. This threshold decision alone does not authorize a deposit, key
generation, activation bypass, or external-state change.
