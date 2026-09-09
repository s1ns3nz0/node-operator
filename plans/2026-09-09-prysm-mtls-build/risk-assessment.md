# Prysm release candidate assessment

Assessment date: 2026-09-09. Integration reviewer: root, under the user's
delegated authority. Reassessment due: 2026-10-08, or immediately upon a
source, patch, dependency, image or advisory change.

## Artifact and executed evidence

- Source: Prysm `51b5a75ebbadf05af22bd2601b5baf7a9e99b66d` with both
  SHA-256-checked patches in `.ci/prysm-mtls/source.lock.json`.
- Linux/amd64 manifest:
  `sha256:6b5d6b0d2a4e3ebf4af5d1924a783ae239f6e1325dd7d100714d1d01cc0393aa`.
- Local OCI index:
  `sha256:8a1d48b8fddaf6a16d151743624e854bd8cf44267b41e97de53aa2506cd1494f`.
- Docker module verification, both mTLS package test suites, validator-node
  configuration tests and complete validator build passed. Final-image
  execution with no network passed and exposed all three HTTP mTLS flags.
- Grype 0.111.0, valid DB built `2026-09-08T06:30:10Z`, scanned the exact local
  index. Raw report: `/private/tmp/hoodi-prysm-release-grype-20260909.json`.
  Critical **0**, High **0**, Medium **8**, Unknown **1**. Keep these original
  counts in PR evidence; do not describe the image as vulnerability-free.

## Remediation completed

The first Debian image had Critical 2/High 25. Upgraded Go to 1.26.6 and
the affected crypto, networking, text and gRPC modules with compatible
transitive dependencies. Switched the final runtime to Alpine/musl, actually
rebuilt CGO code and verified final-runtime execution. The first Alpine
candidate still had Critical 4/High 14 in OpenSSL; upgraded libcrypto3 and
libssl3 from 3.5.7-r0 to 3.5.8-r0. No Critical/High exception was needed.

## GO-2026-5932: Unknown, package not included

Primary advisory: <https://vuln.go.dev/ID/GO-2026-5932.json>.
It concerns the unmaintained `golang.org/x/crypto/openpgp` package and its
subpackages, not every package in the crypto module. The scanner matches
module `golang.org/x/crypto v0.56.0`, which has no fix for this advisory.

In the exact Linux builder, `go list -mod=readonly -deps ./cmd/validator`
produced 1,225 package paths with **no** `golang.org/x/crypto/openpgp` or
subpackages. The build now fails if any such path appears. The generated
inventory is included in the final image at
`/usr/share/validator-dependencies.txt`, SHA-256
`a3b7eb02a12e286848189448cd2252f671581b1254bb6533ed0cc4ccf1c7e640`;
the final image inventory was independently checked with no network.

Decision: advisory is not applicable to this exact validator target because
the affected packages are absent from its build dependency closure. This is
not an assertion that OpenPGP is safe, nor a global waiver for x/crypto.
Any future inclusion must block this decision and require removal or migration
to a maintained implementation. Preserve the raw Unknown finding and attach
this assessment to the PR. Generic CI gates have not been globally changed.

## Remaining deployment conditions

Medium findings remain disclosed in the raw scan; no High/Critical finding
is accepted. The assessment does not certify live signing or other images.
The existing deployed Web3Signer scan separately returned Critical 2/High 51.
The hardened candidate has since passed its Docker tests and an ECR rescan
at Critical 0/High 0, at index digest
`sha256:f6f9cbfa9035103640c16499db9316124f89582ff46727e4b393a2950b5fd860`.
That candidate has now been deployed to the signer and DB migration init;
the retained PostgreSQL data passed snapshot-clone rehearsal and the original
volume upgrade. A live GET-only mutual TLS probe at `2026-09-08T17:35:00Z`
verified exactly one public key matching the deposited validator. Evidence:
`/private/tmp/hoodi-001-signer-public-key-20260909.json`, SHA-256
`b1bb84f4afdb2e8fb0b599a36e0b2d02f985c85061ce85a30075bc32fabe9a25`.
This is not signing-duty evidence. The Prysm index above is also published
privately and re-scanned with Critical 0/High 0/Unknown 1. Neither publication
constitutes trusted-release promotion. Preserve retained slashing state,
complete mTLS identity verification and enforce a single fenced validator.
Retain SBOM plus unfiltered scan artifacts with the PR before promotion.

The actual injected Vault 1.20.4 agent image separately scanned at Critical
23/High 138. It is outside the Prysm exception scope. Agent-only remediation
is in progress; this assessment does not approve that image or a Vault server
upgrade. Client and fence are staged at zero replicas. The public signer
Service now selects the fence, and obsolete direct-client ingress was removed
with a non-sensitive backup. Effective network enforcement and actual duties
still require separate verification.

## Future exception decisions

### Beacon candidate: separately verified target

The native Beacon build uses the same pinned Prysm source and checked security
patch, but is assessed separately from the validator executable. Frozen local
index `sha256:d0f012f8a779aa8f2f385579292e09f2dbe1db7ae42ccb401caac46d9bc1f324`
passed offline, read-only, UID1000 version/help execution. The build runs core
block, JWT and flag tests; the latest guard-only change reused that build cache.
The final executable SHA-256 is
`962c35d4ca2d1abaa930055ac368984537e57da428aa4ad993d5a40ec5a426c5`.

Its 1,211-package dependency closure contains no affected OpenPGP package or
subpackages, and a build guard now rejects future inclusion. Inventory SHA-256:
`b61bec4707b18e5020714595c1fcfe29682c7e063a3e74d03d92c563978cbafe`.
Thus GO-2026-5932 is not applicable to this exact Beacon target, not waived for
the whole module. Preserve its raw Unknown match. Exact-image Grype0.111.0
with valid DB built2026-09-08T06:30:10Z and explicit no-exclusion configuration
returned C0/H0/M8/Unknown1, ignored0. Scan SHA-256:
`a7f4ae03718cbb17dc975b2ffe76de47d01e91af4d2684a815b7039fe29dc648`.
This is local candidate evidence only, not publication, live compatibility or
CI attestation. No Critical/High exception is accepted. The assessment expiry
and change-triggered reassessment rules above apply independently to this image.

Apply `docs/operations/prysm-risk-acceptance.md` to each unavoidable Prysm
library finding. This assessment accepts no Critical/High exception today.
For any future exception, attach actual remediation attempts, applicability
and impact analysis, implemented controls and their verification, remaining
risk, a named reviewer, expiry and a concrete follow-up action to the PR.
An exact digest/finding match and valid assessment are required before an
automated exception path is used; documentation alone does not bypass the
unchanged generic CI gates. Report accepted findings as
`passed-with-exceptions`, never as remediated or a clean scan.

## Other runtime findings and upgrade boundary

The complete running-image inventory found additional findings in Nethermind,
Beacon, audit relay, Vault injector and ZAP-based health proxies. See the
latest runtime checkpoint in `evidence.json` for artifact-specific counts.
None inherits a Prysm exception. Nethermind's unchanged 1.39.3 application on
patched .NET10.0.11 passed exact-file comparison, offline execution and C0/H0
scan; it is still local. The Go1.26.6 audit relay candidate passed Docker tests
and a private registry rescan with no findings; publication is not deployment
or a trusted CI attestation.

Do not upgrade the Vault server merely because an Agent build passes. The
[official Agent guidance](https://developer.hashicorp.com/vault/docs/agent-and-proxy/upgrade)
describes older Agent/newer Server API compatibility, not blanket forward
compatibility. Actual Kubernetes auto-auth, template rendering and lifecycle
behavior must be exercised for the chosen pair.

[Vault2.0 important changes](https://developer.hashicorp.com/vault/docs/updates/important-changes)
also require a valid Vault token for generate-root/rekey operations in addition
to recovery shares. The user's existing recovery-only ceremonies therefore
need an explicitly reviewed transition before any server upgrade. Do not
silently enable unauthenticated access as a workaround. Preserve Raft backup,
restore isolation and rollback requirements; an Agent-only image does not
remediate the still-running Vault server.
