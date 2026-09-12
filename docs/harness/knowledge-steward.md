# Knowledge steward

`$knowledge-steward` is an explicit user-invoked orientation skill for a new
collaborator or a return to the repository after a gap. It makes the current
state understandable without treating an earlier conversation as durable
evidence.

## Authority and evidence boundary

The steward is read-only by default. Its evidence may come only from live
repository state:

- `AGENTS.md`, `README.md`, and relevant `docs/` material;
- current task contracts, plans, evidence, and reports;
- accepted decision records and current product specifications;
- relevant `git log`, `git diff`, status, and affected file state.

Chat memory, an agent's recollection, and an external wiki are not evidence
sources. `docs/` is the canonical wiki, and an external wiki must not become an
independently editable source of truth.

For a user who has a raw service idea rather than a request to orient to an
existing repository state, direct them to the explicit `$requirements-steward`
workflow. The knowledge steward does not synthesize, approve, or promote new
requirements.

The ordinary result is a chat response. Only an explicit user request for a
point-in-time handoff authorizes persisting a report, which must identify the
Git state and source artifacts it reflects. A handoff does not authorize
implementation, configuration changes, external communication, or publication.

## Required orientation order

The response follows this fixed order:

1. What is needed from the user, if anything.
2. Product purpose and current behavior.
3. Architecture map and sources of truth.
4. What changed in the relevant history or worktree.
5. Active work, validation state, blockers, and risks.
6. New or potentially unfamiliar terms, each linked to its canonical source.

Distinguish observed facts from inference. If an artifact is missing,
inconsistent, or does not establish a claim, say so rather than filling the gap
from chat context.

## Roles and contradiction handling

Terra owns the synthesis. Luna may collect a bounded set of Git/file evidence
when that reduces ambiguity. Luna does not synthesize policy or alter files.
Only Sol may resolve a material contradiction among documentation sources, and
must route it through `$ambiguity-gate`. Until that decision is accepted, report
the conflict and its affected work rather than selecting a product direction.

When describing active work, distinguish an approved product specification from
a proposed requirement or decision. A task contract that lacks a link to an
approved product spec is a blocker for material implementation work, not a
gap to infer from chat history.

## Drift audits

After an accepted product specification or decision, or when a user explicitly
asks, the steward may run the pinned Paperthin `ssotize` in read-only audit
mode. The audit can identify scatter or drift and propose a canonical-source
reconciliation plan. It must not mutate files. A user-approved consolidation
becomes normal work: create the required task contract and, when non-trivial,
the plan before making changes.
