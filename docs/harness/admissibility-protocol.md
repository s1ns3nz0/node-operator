# Admissibility protocol

Every durable artifact change passes `$admissibility-gate` before completion,
handoff, or commit. Durable artifacts are versioned sources of truth and
execution records: product behavior, policy, task contracts, plans,
evidence, decisions, reports, learning memos, source, tests, and
repository-local skills. Transient scratch output is excluded.

The gate is a thin router to pinned Paperthin `sip`, not a local copy of its
checks. Read `harness/paperthin.lock` and the pinned release instructions for
the installed interface. It supplements, never replaces, the configured
verification ladder.

## Role ownership

The primary Sol agent assigns these duties in the task contract before work
starts. A worker can report that a check is inapplicable or unavailable, but
cannot waive it, redefine applicability, or call its artifact admissible. Sol
integration rejects missing required evidence rather than inferring a pass.

| Role | Required duty | Evidence it must provide | Boundary |
| --- | --- | --- | --- |
| Luna | Gather scoped evidence; run applicable `factchk` for reality claims and `mandela` for evaluations, metrics, or experiments | Claim/evaluation scope, sources or ground-truth path, command/skill result, timestamp, finding or skip reason | No implementation, waiver, scope carve, or completion decision |
| Terra | Implement within its assigned files; invoke `sip` after each durable artifact change; record its conditional route, `ssotize` audit, applicable `detool`, and `re0` for durable non-code artifacts | Changed artifacts, `sip` result, every routed check or skip reason, findings, one correction and recheck if used | Cannot waive evidence, perform final admission, or choose an `autobahn` carve |
| Sol | Integrate; run the required context-free `shower`; review the complete `sip` evidence; control `autobahn`, ambiguity escalation, and user-invoked `hate` | Fresh-reader verdict, integration decision, `autobahn` ledger where applicable, ambiguity/hate references, rejection of missing evidence | Only Sol may accept completion or authorize escalation decisions |

Terra's `sip` record must name Sol's pending or completed `shower` so the
always-required check is visible before integration. Luna and Terra may flag an
unacceptable or material finding, but only Sol routes it and owns its outcome.

## Paperthin route

Terra invokes `sip` for the changed artifact set, with Luna supplying the
scoped truth-evidence checks and Sol supplying the fresh-context `shower` at
integration. Together they preserve the following `sip` route:

| Check | When it runs | Required evidence outcome |
| --- | --- | --- |
| `shower` | Always | Fresh, context-free comprehension verdict and findings |
| `factchk` | A reality-grounded claim is asserted | Per-claim verification or falsification |
| `mandela` | An evaluation, metric, or experiment is defined or reported | Ground-truth leakage audit |
| `ssotize` | Always, audit mode | Consistency/scatter result and canonical-source plan if needed |
| `detool` | The artifact claims portability, tool-neutrality, stack-agnostic durability, or cross-agent reuse | Portability finding or skip reason |
| `re0` | A durable non-code artifact changed (requirements, decisions, plans, reports, or skill instructions) | Clean-v0 result and findings |

Record a conditional check as `skipped` only with its precise reason. A missing
installed capability is also `skipped`, with `unavailable` and the observed
reason; it is never a pass. `ssotize` may audit without approval, but its
consolidation plan may mutate only after the required approval.

## Completion decision

Classify findings by their operational consequence:

- **Unexplainable** — a `shower` failure: the artifact cannot stand alone or a
  fresh reader had to guess a load-bearing meaning. It blocks completion by
  default.
- **Unreasonable** — a factual claim, evaluation, metric, experiment, or
  requirement lacks support. It blocks completion only if evidence falsifies
  the claim, evaluation, or authoritative requirement. Requirement evidence is
  the applicable accepted product specification, decision record, or task
  contract; do not treat a non-authoritative copy as a requirement source.
- **Unacceptable** — scope violates task authority or guardrails. Run pinned
  `autobahn`: descope the unacceptable part, preserve a safe alternative and a
  descope ledger, then continue the safe remainder at full strength. Honor its
  required stop for unapproved gray-zone carving; a bright-line exclusion does
  not prevent safe independent work.

For one non-material, in-scope finding, a worker may make exactly one
reversible, evidence-based correction and re-run the affected check plus `sip`.
Material findings, a failed recheck, or a repeated finding route to
`$ambiguity-gate`; do not use repeated speculative fixes. That route may block
only the affected work, never unrelated safe work.

## Evidence

For every gate cycle, write an `admissibility` evidence record as specified in
`docs/plan-graph-report.md`: the `sip` run, each check run or skip reason,
findings, classification, correction, recheck, and any `autobahn` ledger. Keep
raw private prompts and conversations out of the record. A task cannot claim
completion while an unexplainable finding or an evidence-falsified
unreasonable finding is unresolved. Sol integration also rejects a gate cycle
whose role-owned required evidence is absent.
