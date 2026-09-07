# Zero-resource Hoodi release bootstrap

1. Add a local-state bootstrap root for the encrypted remote state backend.
2. Add a foundation-network root that owns the Hoodi NAT gateway and exports
   only non-secret identifiers required by the baseline.
3. Convert the baseline to consume foundation outputs rather than a preexisting
   NAT gateway; remove embedded SSM resources.
4. Add isolated ops-access state and explicit lifecycle commands without a
   scheduler.
5. Extend release orchestration and tests for a zero-resource plan/apply/destroy
   sequence. Only after CI and reviewed plans pass may the live environment be
   destroyed and recreated.
