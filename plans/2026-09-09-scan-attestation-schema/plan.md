# Scan attestation schema repair

1. Confirm real failed-run payload and pinned Cosign3.1.2 conversion behavior.
2. Use a versioned custom URI to preserve the existing scan-summary object.
3. Share strict content verification between relay and fence, after cryptographic verification.
4. Exercise real pinned Cosign offline with synthetic keys plus negative fixtures.
5. Review, run CI, merge only after required approval, then verify release end to end.

Terra owns only new scripts/ci/verify-release-scan-attestation.sh and
scripts/ci/test-release-scan-attestation.sh. Root owns workflow changes, existing
fence mocks, documentation and final integration. No deploy in this task.
