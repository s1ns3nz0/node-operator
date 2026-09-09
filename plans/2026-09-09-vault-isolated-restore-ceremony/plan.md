# Real isolated recovery ceremony

1. Revalidate current source and recovery host metadata.
2. Build a host-only, explicit-execute restore and candidate upgrade ceremony with exact image/snapshot/KMS pins, loopback API and local audit sinks.
3. Build constrained administrator-session acquisition for existing grant helper without exposing credentials.
4. Test fail-closed state transitions with mocks and independently review. Publish via normal CI and review.
5. Only after code review, preflight live isolation and execute from user terminal. Actual restore/upgrade evidence remains pending until observed; do not advance existing Vault rollout or validator duty on mock evidence.
