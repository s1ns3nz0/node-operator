# Task contracts

Create a task contract before implementation. It must link every implementation
task to the approved, canonical product specification(s) that authorize its
user-visible behavior. A proposed or unapproved requirement is not authority
to implement. Use `$requirements-steward` when a user has supplied only a raw
service idea or requirements need synthesis. Store it with its plan for
non-trivial work; a trivial task may keep the same fields in its task note.
The contract establishes scope and authority, not a blank cheque for external
actions.

## Classification

A task is **non-trivial** when any configured threshold applies: it uses more
than one agent or model, crosses domains, changes a public API, security, or
data behavior, or needs more than one validation layer. Record the reason when
classifying a task as trivial or non-trivial.

## JSON shape

```json
{
  "id": "2026-08-30-example",
  "title": "Short outcome-oriented title",
  "classification": "non-trivial",
  "classification_reason": ["multiple agents", "public API"],
  "expected_outcome": "Observable result and its user/value boundary.",
  "inputs": ["Relevant models, interfaces, or data assumptions"],
  "constraints": ["Compatibility, privacy, performance, and edge cases"],
  "product_specs": ["docs/product-specs/example.md (approved)"],
  "decision_records": ["docs/decisions/2026-08-30-example.md"],
  "change_points": ["Paths or modules expected to change"],
  "authorization": {
    "repository_mutation": true,
    "external_actions": [],
    "prohibited_actions": ["deploy", "publish", "merge"]
  },
  "delegations": [
    {
      "id": "implementation",
      "tier": "terra",
      "owner": "agent identifier",
      "files": ["src/example/**"],
      "worktree": "../worktrees/example-implementation",
      "branch": "harness/example-implementation",
      "acceptance_checks": ["npm test"],
      "escalation_trigger": "Ambiguous API or security decision"
    }
  ],
  "validation": ["format", "lint", "typecheck", "test"],
  "behavioral_proof": {
    "required": true,
    "user_acceptance_gated": false,
    "observable_surfaces": ["UI checkout", "POST /orders"],
    "proof_type": "ui-screenshot | ui-video | api-cli-transcript | executable-example | service-health-log",
    "acceptance_criteria": ["Primary journey", "Key edge condition"],
    "independent_reviewer": {"tier": "terra", "acceptance-only-brief": true},
    "evidence_location": "plans/2026-08-30-example/evidence.json"
  },
  "admissibility": {
    "required_for_durable_artifacts": true,
    "evidence_location": "plans/2026-08-30-example/evidence.json",
    "unresolved_completion_blocks": ["unexplainable", "unreasonable:falsified-evidence"],
    "role_assignments": {
      "luna": ["scoped evidence gathering", "applicable factchk", "applicable mandela"],
      "terra": ["implementation sip", "conditional check record"],
      "sol": ["integration shower", "autobahn", "ambiguity and hate gates", "completion decision"]
    },
    "integration_rejects_missing_required_evidence": true
  },
  "risks": ["Specific remaining risk and mitigation"],
  "status": "planned"
}
```

Use a stable, date-prefixed `id`. A delegation's file list must be narrow
enough to prevent collision. Any change outside that boundary is escalated to
the primary agent before it is made.

`product_specs` must contain the paths of approved specifications, not merely
related proposals. If no approved specification exists for a material product
behavior, complete the `$requirements-steward` approval route before task work
that implements it. A task may reference an approved specification together
with a later proposed decision record only when the planned work avoids the
unapproved behavior.

`admissibility` records that `$admissibility-gate` is required after each
durable artifact change and identifies its evidence. An unacceptable scope
finding is handled by `autobahn` descope rather than by treating the unsafe
part as complete. It must assign Luna, Terra, and Sol's default duties when
those roles participate; workers cannot waive a required check, and Sol
integration rejects missing required evidence. See
`docs/admissibility-protocol.md`.

`behavioral_proof` makes `$show-dont-tell` mandatory before completion when
the expected outcome has observable behavior. It specifies the surfaces and
acceptance criteria so an independent reviewer can receive only those criteria
and the artifacts, never the implementation narrative. A demo is visible to
the user when practical, but blocks approval only when
`user_acceptance_gated` is explicitly `true`.

For a purely internal refactor, set `required` to `false` only with a
`no_observable_change` evidence record that lists each considered surface, the
comparison/check performed, result, and rationale. The independent reviewer
must assess that exception; calling a change internal is not evidence.

## Ambiguity fields and acceptance

For a material ambiguity, add an `ambiguity` object with affected node IDs,
risk-adjacent status, canonical sources, `readchk`/`autobahn` evidence
references, a safe correction attempted (if a failure occurred), and the
decision-record path. The primary Sol owner must be named for every
`$grill-me` interview. Only explicit user approval makes an outcome accepted.

Create or update its decision record first, then reconcile product
specifications and the task contract/plan. An unresolved material fork blocks
only its affected work. Record a `hate` result only when the user explicitly
invoked it under the timing rules in `docs/ambiguity-escalation.md`.
