# Node Operator EKS — Implementation Tasks

## Phase 1 — Contracts and safety rails

### T-1: Scaffold repository and shared-contract integration

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-3, US-4
- **Description:** Establish TypeScript/package tooling, import the versioned `compliance-contracts` package, create evidence-envelope validation fixtures, and document the no-secret/no-mutation boundary.
- **Acceptance:** Type checking and contract tests pass; prohibited evidence fixtures are rejected before export.
- **Dependencies:** none

### T-2: Create Terraform security baseline

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-1, US-4
- **Description:** Add Terraform modules and non-secret variable schemas for private EKS, a two-AZ managed Linux node group (`min=2`, `desired=2`, `max=3`, validated `m7i.2xlarge`-class default), EBS CSI/encryption, Pod Identity, CloudTrail, AWS Config, and narrow IAM. Include offline fixture inputs only.
- **Acceptance:** `terraform fmt -check`, `terraform validate`, and policy tests pass with no public endpoint, unencrypted volume, broad IAM finding, or node-group capacity outside the approved bounds.
- **Dependencies:** T-1

### T-3: Define workload hardening baseline

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-2, US-4
- **Description:** Add namespace, service account, RBAC, default-deny NetworkPolicies, pod security contexts, resource standards, and policy tests shared by both clients.
- **Acceptance:** Manifest validation and policy tests reject privileged workloads, root execution, writable root filesystems, and unbounded egress.
- **Dependencies:** T-1

## Phase 2 — Decision-gated node configuration

### T-4: Render Prysm testnet workload

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-2
- **Description:** Add a pinned Hoodi Prysm StatefulSet overlay with an encrypted 500 GiB `gp3` PVC (6,000 IOPS/250 MiB/s), probes, limits, required anti-affinity/node selection, peer/DNS/telemetry policy, and allow-listed metric configuration.
- **Acceptance:** Rendered manifest names Hoodi; tests verify persistent storage performance, hardened settings, probes, and non-co-location with Nethermind.
- **Dependencies:** T-2, T-3

### T-5: Render execution-client testnet workload

- **Status:** pending (select and record the approved release/digest when implementation begins)
- **Wired:** no
- **Verified:** no
- **Requirements:** US-2, US-4
- **Description:** Select the Hoodi-compatible Nethermind stable release at task start, record its OCI digest, then add a separate pinned StatefulSet with an encrypted 2 TiB `gp3` PVC (10,000 IOPS/250 MiB/s), probes, limits, required anti-affinity/node selection, and allowed network paths.
- **Acceptance:** Tests reject floating image tags and prove it does not share Prysm storage, node placement, or service identity.
- **Dependencies:** T-2, T-3

### T-6: Implement allow-listed evidence collection and export

- **Status:** blocked (shared transport contract)
- **Wired:** no
- **Verified:** no
- **Requirements:** US-3
- **Description:** Configure collector filters and exporter translation for IaC, Kubernetes posture, AWS Config/CloudTrail summaries, and permitted metrics. Import the shared contract, add an exporter-only Pod Identity service account/route-scoped `execute-api:Invoke` policy, sign `POST /v1/evidence` requests with SigV4, and implement the encrypted 24-hour retry queue.
- **Acceptance:** Fixture tests prove schema/provenance/timestamp fields, redaction before buffering, invalid-record drops, route-only SigV4 authorization, idempotent `202` handling, 24-hour retry expiry, no direct S3/PostgreSQL permissions, and non-sensitive health signals.
- **Dependencies:** T-1, T-2, T-3, shared transport contract

## Phase 3 — Delivery assurance and proof

### T-7: Establish OPA policy-as-code foundation

- **Status:** complete
- **Wired:** yes
- **Verified:** yes (OPA 1.17.0, Conftest 0.69.0, and ShellCheck 0.11.0)
- **Requirements:** US-4
- **Description:** Create `policy/` Rego/data/test layout, CODEOWNERS ownership with `@fjybjinsu` as the required sensitive-path reviewer, an expiring exception register, JSON evidence schema, normalizer fixtures, `opa test`, Conftest rendered-manifest checks, and one-purpose `scripts/ci/` command boundaries. Document the full open-source guide in `docs/policy-as-code.md`.
- **Acceptance:** Each initial rule has passing and failing fixtures; OPA rejects missing evidence and expired/incomplete exceptions; sensitive-path fixtures require `@fjybjinsu` review and reject self-approval; workflow YAML contains only flow/permissions/pinned-action declarations and calls to independently testable scripts.
- **Dependencies:** T-2, T-3

### T-8: Implement required OPA-governed PR gates

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-4
- **Description:** Collect JSON evidence from Gitleaks, OSV-Scanner, Semgrep, Zizmor, Checkov Terraform/Kubernetes, formatting, and offline Terraform validation. Normalize evidence, invoke OPA as the required status check, and publish JSON/SARIF outputs.
- **Acceptance:** Deliberately insecure, secret-bearing, incomplete-SCA, unpinned-workflow, and insecure-IaC fixtures each yield an OPA `block` decision and fail the PR gate; clean fixtures pass.
- **Dependencies:** T-7

### T-9: Add posture, build, and release-eligibility evidence

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-4
- **Description:** Add scheduled GitHub API/Scorecard posture collection, Syft SBOM, optional Grype scan, Cosign verification, and SLSA provenance evidence. Add OPA decisions for trusted builder, digest matching, scan age, and review posture. Do not publish or deploy.
- **Acceptance:** OPA blocks fabricated/mismatched digest or provenance fixtures and reports repository-posture drift; artifacts are keyed by commit SHA or digest.
- **Dependencies:** T-8

### T-10: Produce read-only boundary proof

- **Status:** pending
- **Wired:** no
- **Verified:** no
- **Requirements:** US-1, US-2, US-3, US-4
- **Description:** Create reproducible local proof showing secure rendered manifests, a redacted valid evidence export, rejection of a sensitive fixture, and absence of mutation endpoints/IAM actions. Obtain an independent acceptance review.
- **Acceptance:** API/CLI transcript or test output and review record show the primary evidence journey, redaction edge, and no-mutation boundary. No AWS access is performed.
- **Dependencies:** T-4, T-5, T-6, T-9

## Verification matrix

| Area | Evidence |
| --- | --- |
| Types/contracts | typecheck and schema fixture tests |
| Terraform | fmt, validate, static policy checks |
| Kubernetes | render, schema validation, policy tests |
| Security | IaC/container scan and SBOM/evidence record |
| Boundary | explicit no-deploy CI inspection, IAM action tests, sensitive-data rejection test |
