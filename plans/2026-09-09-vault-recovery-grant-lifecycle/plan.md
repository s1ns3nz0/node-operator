# Temporary recovery grant lifecycle

1. Inspect reusable recovery contracts and live role boundaries without secret access.
2. Implement explicit, bounded grant create/revoke operations with mock tests and dry-run default.
3. Independently review least privilege, idempotency, cleanup and non-sensitive outputs.
4. Run checks and publish through ordinary CI/review. Grant execution and snapshot recovery are separate subsequent steps, not implied by this PR.

KMS grants have eventual consistency and require explicit revocation. The host IAM expiry deny is a separate safeguard, not grant deletion. Reference: https://docs.aws.amazon.com/kms/latest/developerguide/grants.html
