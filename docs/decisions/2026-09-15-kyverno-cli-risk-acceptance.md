# Temporary Kyverno CLI risk acceptance

Decision date: 2026-09-15. Review deadline: 2026-10-15 (UTC).
The repository operator explicitly accepted these residual risks in conversation.
This is a risk acceptance, **not** a finding of non-applicability or a clean scan.
It does not waive required pull-request review or authorize unrelated exceptions.

## Assessed findings

| Finding | Reviewed dependency | Risk and evidence |
| --- | --- | --- |
| GO-2026-6225 | github.com/chrismellard/docker-credential-acr-env v0.0.0-20230304212654-82a0ddb27589 | A malicious hostname matching the permissive ACR pattern can receive an Azure credential. Binary analysis reports ACRCredHelper.Get present. No fixed version was reported. |
| GO-2026-5932 | golang.org/x/crypto v0.56.0 | Unsupported OpenPGP functionality is unsafe by design. Binary analysis reports affected OpenPGP packages/symbols present. No fixed version was reported. |

The reviewed upstream source is Kyverno v1.19.1, commit
`40ec788d48bb28d83dbf85538e962a59db9d45c6`.
The inspected candidate image digest is
`sha256:bb9ba5c0f18e76dc376acbd70653b9b45b6d78dcd4eb4e13641b652ede69130a`;
its `/ko-app/kubectl-kyverno` binary SHA-256 is
`fd049f973d08fad9e6041a56aea901eda5d99a645c2f9a60da06ccbc65996c1f`.
Grype 0.111.0 reported two Unknown findings and zero High/Critical findings.
Those two Unknown findings are the two advisory/package/version pairs above.
This was the local diagnostic scanner, not the release toolchain. The release
installer `scripts/ci/install-release-sca-tool.sh` pins Grype **0.118.0** with an
archive checksum. Run `34915568618` generated the same two findings using that
version for candidate `sha256:585fb3f2a765a0262fcdc6e8be903e2c8e5d2f437a2c7d62f8967ac8eea9c8f1`.
The original acceptance implementation incorrectly required the local version
and rejected this valid release-toolchain report. The verifier must require the
release-pinned version; this correction neither adds accepted findings nor
changes the accepted dependency/build scope.
govulncheck 1.1.4 binary/symbol analysis confirms code presence, not exploitation.
No whole-program proof that the vulnerable paths are unreachable was obtained.

## Scope and compensating controls

Acceptance is limited to this repository's pinned Kyverno CLI build inputs and
its Kubernetes resource-migration hook. It does not cover the Kyverno admission
controller, other images, interactive/general-purpose CLI use, OCI evaluation,
Azure registry authentication, or OpenPGP processing.

The inspected migration command directly performs Kubernetes resource and CRD
operations. This reduces expected exposure but does not establish unreachability:
the image contains the full CLI and its initialization paths.
The deployment must use only the reviewed migration invocation, supply no Azure
credentials or OpenPGP material, and retain the reviewed hook service account and
RBAC. These are deployment conditions to verify before live use, not a claim
that every live control is already installed.

Publication must preserve the raw SBOM, scanner report, and unmodified finding
counts. A separate digest-bound risk decision must identify the accepted findings,
policy/build binding and expiry, and be signed and verified with Cosign. A rebuilt
image is a new candidate: it must be scanned and verified again. Only exact
reviewed finding/package/version matches can be accepted; other Unknown, High,
or Critical findings remain blocking. Global release scan policy is unchanged.

The implementation entry point is `scripts/release/publish-kyverno-cli-image.sh`;
the build recipe and source lock are in `.ci/kyverno-cli/`. Only the main-branch
`image-publish.yml` identity in `s1ns3nz0/node-operator`, authenticated through
GitHub Actions OIDC and Cosign, may issue publication evidence. Verification must
bind the workflow revision and image digest, not merely find any valid signature.
The publication artifact retains non-secret evidence under `evidence/`, including
the scanner/database metadata. The original diagnostic scan used the exact image
digest above; the raw local files are in `/private/tmp/node-op-kyverno-scan.u3WQKv/`.
Temporary local files are investigation inputs, not durable approval authority.

Before live installation, integration must inspect the rendered pinned chart's
post-upgrade migration Job (command `migrate --resource ...`), its target resources,
service account, Role/ClusterRole bindings, environment, volumes and credentials.
Unexpected commands or credential mounts block installation. The renderer is
`scripts/release/kyverno_bootstrap_inputs.py`; this document does not approve
arbitrary arguments simply because the executable is named Kyverno.
Only catalog-promoted, verified images may be installed; no early live trial is
authorized by this exception. Record the actual rendered-manifest review alongside
the publication evidence before invoking `apply-kyverno-bootstrap.py`.
The publisher necessarily pushes an immutable candidate tag before registry
scanning. Its presence in ECR is not approval: neither that tag nor an unreviewed
digest may be added to installer inputs or used for live deployment. The existing
catalog proposal renderer requires explicit retained risk evidence for v2 records
and revalidates the full decision before proposing a row. The caller must verify
Cosign first; publication alone therefore does not unblock live installation.

## Verified publication candidate

The [Kyverno-only publication run 34916913146](https://github.com/s1ns3nz0/node-operator/actions/runs/34916913146)
succeeded from main revision `7609863012c2c468b291f7189e8509debf908eb2`.
The proposed catalog image digest is
`sha256:9dbbfdb7948a996674d0a99304460ab93863692ce40e62feb64dc2fc7ed6a8e6`.
An independent Cosign 3.1.2 verification against ECR checked the image signature
and four attestations (risk decision, raw Grype report, SBOM and provenance),
requiring the exact main workflow identity, GitHub OIDC issuer and source revision.
Each independently verified predicate matched the downloaded publication evidence
and image subject. No live migration or validator activation is implied.

Publication record SHA-256:
`27a386256fa499b91cc976cd039678e1ec3258c88a6f4c7130b41be3853bf1ed`.
Risk decision SHA-256:
`a558a6a558f16b59fd556ac143d71c21991fe8715d52a344df9dd1f01f9b7106`.
The original blocked scan remains preserved; the two accepted Unknown findings
were not converted into a clean scan. The expiry and pre-installation migration
control review above still apply.

## Remaining risk and exit criteria

The vulnerable code remains available in the executable. Changed invocation,
initialization behavior, credentials or inputs could expose it. Source pinning,
signatures and short-lived migration usage do not repair either vulnerability.
This temporary exception is accepted to proceed with the portfolio deployment;
it is not an assurance of absence of exploitable behavior.

Reassess before the deadline, on any build-input/dependency change, new relevant
advisory, or use outside the migration hook. Prefer removal of the unnecessary
credential/OpenPGP paths or a reviewed migration-only build. Do not automatically
renew the exception. The old candidate remains unpublished as an approved image
until the new reviewed publication path and downstream verification pass.
Expiry is exclusive at `2026-10-15T00:00:00Z`: subsequent publication or migration
requires a new reviewed decision. The repository operator owns reassessment;
the integration owner must check expiry and changed inputs before deployment.
This is a release/deployment gate, not an automatic runtime shutdown mechanism.

Advisories: <https://pkg.go.dev/vuln/GO-2026-6225>,
<https://osv.dev/vulnerability/GO-2026-5932>.
