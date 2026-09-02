# T-1: offline Compliance Ops evidence producer

1. Bind the producer to `@compliance-ops/contracts` commit `93aa78d`.
2. Validate v1 envelopes, source allow-lists, size caps, and prohibited data.
3. Generate stable evidence identifiers and classify retryable responses.
4. Build an `execute-api`/`ap-northeast-2` SigV4 request configuration without
   obtaining credentials or sending a request.
5. Exercise all behavior through an in-memory transport; default delivery is
   disabled until authorized endpoint and Pod Identity provisioning.
