# Exact-candidate applicability

1. Recheck official GO-2026-5932 affected package paths and extract frozen-image binary/dependency identities without rebuilding.
2. Preserve Agent's existing non-sensitive dependency export, bound to its exact runtime binary; read Server/Injector dependency inventory from their frozen images.
3. Add a separate expiring applicability decision: retain raw scan/summary, require exact reviewed evidence and only the one Unknown finding; fail closed on drift, missing evidence, new findings or expiry.
4. Exercise hosted-run artifacts and negative mutations, independently review, then submit one scoped PR.
5. After merge rerun read-only verification; signing and live rollout remain separate.
