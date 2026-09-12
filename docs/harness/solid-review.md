# SOLID review

`$solid-review` is a design review for non-trivial object-oriented production
code and module-boundary changes. It is not a universal code-quality ritual.

Run it after the task plan is formed and before implementation. Terra owns the
independent review; Luna may gather bounded interface/dependency evidence; Sol
accepts, blocks, or routes material architectural choices through the ambiguity
gate. Re-run only when integration changes a public interface, dependency
direction, or module boundary.

Save the verdict as `plans/<task-id>/solid-review.md` and link it from
`evidence.json`. Record reviewed boundaries, applicable/non-applicable
principles, evidence, smallest corrective designs, and required tests. A
material violation blocks only its affected work; a local issue gets one
reversible correction and re-review.
