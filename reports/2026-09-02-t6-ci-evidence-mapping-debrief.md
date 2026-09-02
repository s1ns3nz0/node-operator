# T-6 clean-room debrief: CI evidence mapping

## Scope

Reviewed only the completed T-6 task bundle at `plans/2026-09-02-t6-ci-evidence-mapping`, the T-6 changes from base `5900f5a` through commits `87d15b4` and `34e1c2d`, and the supplied check results. This debrief makes no repository changes beyond this report and does not assess unrelated work.

## Verified facts

- The mapper accepts compact PR and release summaries and produces validated `iac` evidence plus one `kubernetes` evidence envelope per static workload.
- Source IDs are deterministic SHA-256-derived `ci.sha256:` values, so commit SHAs, artifact digests, and workload names are not retained in observability-facing source IDs.
- The input boundary uses allowlists and rejects unsupported fields, raw collector material, invalid digests and commit SHAs, excessive nesting, oversized strings and keys, and oversized collections before the producer is called.
- Delivery remains disabled unless a transport is explicitly injected. The tested injected transport receives the fixed `/v1/evidence` path without an endpoint field.
- `npm run test:ci-evidence-mapper` is registered and is invoked by the contract-registry workflow alongside `test:evidence-producer`.
- Supplied validation evidence: `npm run test:ci-evidence-mapper` passed 7/7 tests; `npm run test:evidence-producer` passed 7/7 tests; `npm run harness:check` checked 9 graphs; and `git diff --check` passed.

## Limits

- The CI workflow run could not be checked locally because the CLI GitHub token returned HTTP 401.
- No delivery occurred and no AWS access, endpoint invocation, deployment, publication, merge, or secret change was performed or assessed.
- This is a clean-room review of the stated artifacts and supplied results, not an independent re-execution of the checks.

## Outcome

T-6 has documented evidence that its local mapper and producer checks pass, and that the mapper enforces the intended redacted-summary and disabled-delivery boundary. The GitHub Actions execution remains unverified locally due to the unavailable authenticated CLI token; no external delivery or infrastructure activity is evidenced.
