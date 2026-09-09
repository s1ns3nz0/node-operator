# Vault gRPC patch

1. Record hosted run34325393574: Server/Agent newly blocked on GHSA-2v4p-qf9q-27wj, gRPC1.83.1; Injector passed.
2. Derive exact module lock hashes for gRPC1.83.2 using pinned Docker Go tooling and verified previous module files.
3. Patch only Server/Agent build dependency requirements and regression contracts; preserve previous candidate verifiers as historical evidence.
4. Build affected candidates once with cached Docker layers. Run runtime compatibility tests and fresh unfiltered scans; do not promote an incomplete/failed candidate.
5. Review new binary/closure proof and new digest selection separately before publication, signing or live rollout.
