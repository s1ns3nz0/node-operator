# Ambiguity escalation

Use `$ambiguity-gate` when a task has competing interpretations, insufficient
requirements, a validation failure with more than one plausible correction, or
a decision that could change scope, ownership, dependencies, behavior, or
risk. It is a routing protocol, not permission to expand a task or make an
external action.

`$admissibility-gate` routes a material finding, failed recheck, or repeated
finding here. Its default completion blocks remain in force while this skill
resolves the affected node; see `docs/admissibility-protocol.md`.

## Routing and stopping rules

1. When a data drop arrives with a thin or missing ask, run the pinned
   Paperthin release's `aim` first. Let it propose the likely intent for a
   confirm/correct response; do not make the user compose an intent from
   scratch. Do not turn a locally answerable detail into an interview.
2. Run the pinned Paperthin release's `readchk` using the relevant task
   contract, plan, evidence, and authoritative source. Use the
   installed release's documented syntax; this harness does not guess it.
3. If the ambiguity is risk-adjacent (security, privacy, data, public API,
   external action, or a conflicting authority), run the pinned Paperthin
   release's `autobahn` before considering an interview. Preserve its evidence.
4. If a check or implementation failure remains, apply **one** safe,
   evidence-based correction when it is reversible, inside the authorized file
   boundary, and does not choose between material product alternatives. Re-run
   the relevant check. Do not make a second speculative correction.
5. Use the separately pinned `$grill-me` skill only if a material fork still
   survives: the alternatives materially differ in user behavior, scope,
   dependency, ownership, security/data risk, or irreversible cost. The
   primary Sol agent owns and conducts that user-facing interview; other tiers
   may prepare evidence but must not substitute for it.
6. Do not treat a response as accepted merely because it is plausible. Record
   the proposed outcome and obtain explicit user approval. On acceptance,
   invoke the pinned Paperthin release's `ssotize` according to its documented
   interface to reconcile canonical sources. Invoke `feynman` only when the
   accepted decision is major and only with explicit user authorization.

Paperthin `hate` is explicitly user-invoked only. It may run after a
non-trivial plan has formed and before an irreversible or high-cost stage, or on
the user's direct request. It returns one root objection and one first-nail
test. It must not run automatically at every stage or as a substitute for
`readchk`, `autobahn`, or a user decision.

If a material fork remains unresolved, mark the affected work `blocked`, with
the fork, owner, evidence location, and the exact user decision needed.
Unrelated work may continue when it is independent.

## Evidence and outcomes

Record the `readchk`, any required `autobahn`, the one safe correction and its
validation result, the interview summary, user approval, `ssotize`, any
explicitly authorized `feynman`, and user-invoked `hate` result in task
evidence. Keep raw private conversation out of repository artifacts; store a
concise factual summary and permitted links or identifiers.

An accepted outcome creates `docs/decisions/<decision-id>.md` first. Then
update the affected product specification and task contract/plan. A decision
record alone never authorizes an implementation change or an external action.

## Decision-record schema and lifecycle

Decision records are Markdown files named `docs/decisions/<decision-id>.md`,
where `<decision-id>` is stable and date-prefixed. Use this shape:

```markdown
# <decision title>

- ID: 2026-08-30-example
- Status: proposed | accepted | superseded | rejected
- Task: <task-id>
- Affected node(s): <node IDs>
- Owner: <primary Sol agent identifier>
- Product spec: <docs/product-specs path, if applicable>
- User approval: pending | approved (<date/reference>) | declined (<date/reference>)

## Context and material fork
## Evidence
- Thin ask/data drop:
- `readchk`:
- `autobahn` (risk-adjacent only):
- Safe correction and revalidation (if a failure occurred):
- `hate` root objection and first-nail test (user-invoked only):
## Options and outcome
## Canonical-source updates
- Decision record: this file
- Product specification:
- Task contract / plan:
## Follow-up and supersession
```

Create the record as `proposed` before the user-facing interview when the fork
is material. It becomes `accepted` only after explicit user approval and the
required canonical-source reconciliation. Mark it `rejected` when the user
declines it; use `superseded` with a link when a later accepted record replaces
it. The decision index is the directory listing and discovery aid, not a second
source of truth.

## Canonical sources

`docs/decisions/<id>.md` is the durable rationale and approval record.
`docs/product-specs/**` is canonical for approved product behavior and user
requirements. The task contract and plan are canonical for this task's scope,
owners, and execution intent. `evidence.json` is canonical for observed command
and skill results. Reconcile conflicts through the accepted decision record and
`ssotize`; do not silently copy a conclusion between artifacts.
