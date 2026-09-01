# Task graph and clean-room debrief

Non-trivial work is stored at `plans/<task-id>/` as `task-contract.json`,
`plan.md`, `graph.json`, `graph.mmd`, and `evidence.json`. `graph.json` is the
status source. Completion creates `reports/<task-id>-debrief.md`; a fresh
agent reads only this bundle, relevant diffs, and checks, then distinguishes
observed evidence from inference.
