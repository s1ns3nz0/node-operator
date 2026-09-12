# Plans, evidence, and reports

Non-trivial work has one artifact bundle under `plans/<task-id>/`:

```text
plans/<task-id>/
├── task-contract.json
├── plan.md
└── evidence.json
reports/<task-id>-completion.md
```

Task IDs begin with `YYYY-MM-DD-`; report filenames inherit that one date
prefix through `<task-id>` and never append another date or timestamp.

## Plan

`plan.md` states outcome, scope, exclusions, decisions (including linked
accepted decision records), intended work order, risks, acceptance checks, and
current implementation status. Each work item has an owner/tier, file boundary,
and definition of done. A blocked item records a concrete blocker, owner, and
required next decision.

## Evidence

`evidence.json` maps every acceptance check and ambiguity-gate action to a
command or skill, exit status/result, timestamp, summary, and any
waived/not-applicable reason. It also contains an `admissibility` entry for
every durable-artifact gate cycle. A completion report links changed paths,
plan, evidence, risks, decisions, and follow-up.

### Behavioral proof

For every task with observable behavior, `evidence.json` records the selected
proof, acceptance criteria, independent review, gaps, and Sol's integration
verdict. An internal refactor that omits proof uses a reviewed
`no_observable_change` entry instead.
