# SSM retention integration: clean-room debrief

## Scope and method

This is a clean-room, code-stage debrief. It was prepared from the completed
task bundle at `plans/2026-09-08-ssm-retention-integration`, the diff from
`origin/main` in the designated integration worktree, and the supplied local
check results. It does not assert overall task completion.

The bundle assigns Sol as integration/security owner. The bounded wrapper and
test work requested Terra but records an actual inherited GPT-5 fallback;
there is no separate Terra model-run record in the supplied material.

## Observed in the diff

- `infra/ops-access` adds a nullable, exact-ID retained-host opt-in, guarded
  EBS representation, basic monitoring, retained-host discovery and lifecycle
  preconditions. It also conditionally retains existing endpoint ingress
  ownership and moves the two legacy uncounted ingress addresses to `[0]`.
- The release wrapper now requires a private absolute saved-plan path, renders
  plan JSON, distinguishes reviewed retention from fresh creation, hashes the
  saved plan before apply, and disables direct destroy. Its fresh-plan checker
  derives an exact allowed resource/type set from endpoint and ingress flags,
  requires create-only changes, and rejects omissions or extra managed
  resources.
- The retained-plan guard and test scripts cover the nine-address retained
  boundary and adversarial fresh-plan cases, including extra IAM, update,
  delete, replacement, missing profile, missing scope-variable value, and an
  isolated endpoint configuration. CI and release-bundle wiring include these
  checks.
- Migration documentation explicitly describes the reviewed host representation
  as a read-only, non-authoritative private preview and requires planning again
  from the canonical state owner before an execution decision.

## Observed validation evidence

The bundle records 91 harness graphs, 77 passing OPA tests, and
`harness:verify` passing all adapters while rejecting deliberate insecure
fixtures. The supplied integration record additionally states that the four SSM
scripts, release-bundle and bootstrap-contract checks, and cached
Terraform-image basic-monitoring/provider-free EBS tests passed. Following the
scope fix, wrapper, retained-plan, and script-quality checks were rerun and
passed.

The independent-review record says the initial fresh-mode check did not bound
non-instance resources. The remediation is recorded as exact flag-derived
resource/type validation, create-only actions, and before/after consistency.
Sol later identified that a missing endpoint scope-variable value could be
accepted as null. Root corrected the wrapper to require a `value` member for
all three scope variables and added an isolated-endpoint missing-value negative
case. Sol independently reviewed the wrapper, Bash changes, and diff, with
the supplied result recording pass and approval for publication.

## Inference and remaining gates

The code and supplied tests support the inference that the wrapper now has a
narrower local acceptance boundary for the reviewed retained plan and for
declared fresh configurations. This is not proof that a real AWS plan will
meet that boundary or that an apply is safe.

Do not treat this debrief as evidence of overall completion, hosted admission,
normal merge, a fresh AWS-backed plan, full release validation, live apply, or
state migration. The bundle explicitly records `hosted_admission: pending`,
`live_apply: false`, and `state_migration: false`; its graph has review in
progress, integration pending, and this debrief node pending. Actual hosted PR
admission remains required before normal integration. Any canonical-owner
reconciliation or isolated S3 migration requires a new saved plan and
independent review; a copied private-state plan is not authority.

The recorded residual limitations are: no full AWS-backed fresh plan was
demonstrated; the copied retained plan was noncanonical and unapplied; and the
private same-user plan-directory assumption does not prevent a malicious
same-UID final-open race.
