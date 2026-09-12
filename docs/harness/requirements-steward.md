# Requirements steward

`$requirements-steward` is an explicit user-invoked workflow for converting a
raw service idea into a repository-local, approved product requirement and its
execution starting point. It is the harness adaptation of `write-a-prd`; it
does not create, update, or request a GitHub issue.

## Outcome and authority

The workflow produces, in order:

1. A proposed `docs/product-specs/<area>.md` based on the requirement template.
2. A proposed, date-prefixed decision record in `docs/decisions/` that links
   the product-spec path and records the required approval.
3. An approved canonical product specification only after explicit user
   approval is recorded in that decision record.
4. A task contract and, when the classification is non-trivial, the required
   `plans/<task-id>/` plan/evidence bundle for subsequent implementation.

The proposed specification is an artifact for review, not implementation
authority. Product behavior becomes canonical only after explicit approval.
Every implementation task must link to the approved product-spec path in its
task contract. A decision record alone does not authorize code changes.

## Required route

1. Read `AGENTS.md`, `harness.config.json`, this guide,
   `docs/task-contract.md`, `docs/ambiguity-escalation.md`, and the existing
   product specs and decisions relevant to the area.
2. Terra owns requirement synthesis. Luna may gather bounded repository or
   user-authorized external evidence and records findings; Luna neither chooses
   product direction nor promotes requirements. Sol owns material ambiguity,
   acceptance, and the final approval boundary.
3. For a thin raw idea, use the pinned Paperthin `aim` to state the likely
   intent and ask the user to confirm or correct it. Use `readchk` against
   available evidence and repository sources. For risk-adjacent requirements,
   run `autobahn` before selecting a direction.
4. Draft the requirement with
   [the product-spec template](product-specs/requirement-template.md). Preserve
   open questions rather than inventing answers.
5. If alternatives still materially differ in behavior, scope, dependencies,
   ownership, security/data risk, or irreversible cost, create the proposed
   decision record and have the primary Sol agent run `$grill-me`. Do not use
   an interview for locally answerable details.
6. Obtain explicit user approval. Record the approval reference and mark the
   decision `accepted`; then use the pinned Paperthin `ssotize` according to
   its documented interface to reconcile the product specification, decision,
   and task artifacts. If approval is withheld, retain a clearly proposed
   record and do not create implementation authority.
7. Classify the authorized follow-up using `docs/task-contract.md` and create
   its task contract and any required plan only after the requirement is
   approved.

Run `$admissibility-gate` after each durable artifact change and record its
evidence. Route material or repeated findings through `$ambiguity-gate`.

## Scope of the adapted workflow

The workflow keeps the useful substance of PRD creation—problem framing,
users, behavior, constraints, acceptance, terms, and open decisions—while
keeping the repository as the sole durable authority. It creates no GitHub
issue, does not publish externally, and does not begin implementation without
an approved product specification.
