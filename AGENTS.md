# Node Operator Harness

This repository uses the local Codex harness. Read `harness.config.json` and
`docs/harness/` before a non-trivial change. Create `plans/<task-id>/` with a
task contract, plan, graph, and evidence before implementation; record model
fallbacks and keep one primary Sol owner for integration.

Use Luna for bounded reconnaissance, Terra for isolated implementation and
independent review, and Sol for security decisions and final integration.
`reports/<task-id>-debrief.md` is a clean-room summary written by a new agent
that receives only the completed task bundle, relevant diffs, and checks.

No agent may deploy, publish, merge, alter secrets, or access production
without explicit task-level authorization. CI evidence must remain non-sensitive.
