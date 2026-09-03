# CI workflow hardening plan

1. Record the workflow dependency graph and validate existing contracts.
2. Refactor PR scanner evidence into a producer/consumer workflow boundary.
3. Add a trusted default-branch platform-posture evaluation path.
4. Pin and verify scanner-image supply-chain inputs.
5. Reproduce Terraform and release build toolchains, then consolidate policy validation safely.
6. Run validation, obtain Terra independent review, and write the clean-room debrief.

Remote push, image publication, digest promotion, and read-only repository-administration inspection are authorized. Deployment, credential changes, and branch-protection changes remain out of scope.
