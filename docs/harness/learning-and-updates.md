# Learning memos and template updates

Every completed non-trivial task produces a short learning memo in its
completion report or a linked `reports/` document. It records only reusable
constraints, observed failures, and concrete harness gaps; it does not copy
private data, transient chat content, or unsupported conclusions.

Use this structure:

```markdown
## Learning memo

- Context: task ID and affected harness area
- Observation: evidence-backed behavior or failure
- Reusable lesson: narrowly stated rule or gap
- Proposed action: none, project-local correction, or template candidate
- Human approval: pending | approved | declined, with date
```

Project-local improvements may be made under the normal task contract.
Promoting a lesson into this reusable template requires explicit human approval,
a reviewable diff, and the relevant validation checks. Do not silently turn a
single workaround into global policy. Template, Paperthin, adapter, and model
policy upgrades are all versioned changes with evidence and compatibility
checks.
