# Runtime acceptance gaps

The UC numbering here follows `docs/operations/hoodi-validator-lifecycle.md`.
The older `validator-key-operations.md` groups the same controls differently;
its isolation and failover requirements are not waived by that numbering.

## Before enabling the existing validator

- Replace only the signer TLS record with SAN-bearing credentials. Verify the
  resulting live connection with Go's strict hostname and CA validation.
- The local render now uses Prysm's image entrypoint, an explicit writable data
  path, Go HTTP `SSL_CERT_FILE`, a fixed-name StatefulSet Pod, and a separate
  signing-fence Service. These are contract-tested but not live-proven.
- The local fence checks the exact client Pod name, UID, labels and IP on every
  renewal and the local NetworkPolicies remove direct client-to-signer access.
  This is not cryptographic client mTLS. The existing operation contract
  requires mutually authenticated, audience-bound signing requests; source-IP
  and Pod-UID checks alone do not meet it. Add and verify that authentication
  path before enabling duties; this checklist does not waive the requirement.
- The local proxy bounds API calls and each connection by a monotonic Lease
  deadline and tests stale/future/malformed state, CAS races, API failure,
  restart, duplicate sources, existing connections and expiry. Independent
  review and a live fail-closed exercise are still required.
- The local image workflow now produces digest-bound signature, SLSA v1,
  CycloneDX SBOM and vulnerability attestations. The local collector verifies
  these with Cosign plus regenerated Syft/Grype evidence. Behavioral tests
  pass, but use mocks: no fence image has been published or promoted, and the
  pinned installer has not run on the intended Linux runner. Real exact-digest
  verification and reviewed delivery remain mandatory before deployment.
- Verify exact private `active_ongoing` state and slashing PVC/database
  continuity before the zero-to-one activation transition.

## Negative controls and recovery

- Client-to-Vault, CI-to-signer, and cross-set access denial need observed
  results; manifest assertions alone are not live evidence.
- Existing role-revocation evidence demonstrates rejected fresh authentication
  after a signer restart. It does not establish revocation of already loaded
  keys or previously issued Vault tokens.
- A zero desired replica count alone does not prove old Pods are gone. Verify
  actual Pod absence and effective fencing before exercising role revocation.
- Recovery requires an empty Lease, whereas fence shutdown retains its holder.
  An explicit expired-holder release procedure is required before recovery:
  exact Lease and retained PVC identity, stopped controllers and absent Pods,
  compare-and-swap and fresh readback, under exclusive reviewed maintenance.
  A Lease-only CAS cannot prevent a separate controller from being scaled.
- Preserve the existing slashing database. Use synthetic offline keys for
  intentional conflicting-signature tests, never the real Hoodi key.
- Require an actual successful duty before interruption and another duty after
  reviewed restoration, correlated with signer, Beacon and archived evidence.
- Keep role-action audit evidence distinct from bootstrap probes and signature
  outcomes. Do not call a collected record or an assignment a successful duty.

No full UC-2 through UC-5 pass is claimed by this checklist. Commit `74c6b06`
is a tested local checkpoint, not an approved image, deployed controller, or
runtime result. No new deposit,
key onboarding, database reset, voluntary exit, or all-resource deletion is
authorized by it.
