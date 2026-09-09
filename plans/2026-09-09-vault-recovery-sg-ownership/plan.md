# Recovery SG ownership correction

1. Remove only inline empty declarations for directions already owned by standalone rule resources; preserve explicitly denied opposite directions and default SG.
2. Correct boundary regression tests so reintroducing dual ownership fails.
3. Independently review and verify a refresh-backed no-change plan against the new recovery environment; do not apply the old two-update rule-removal plan.
4. Publish and merge through existing review/CI, retain public creation/readiness/drift evidence, and continue isolated recovery preparation.
