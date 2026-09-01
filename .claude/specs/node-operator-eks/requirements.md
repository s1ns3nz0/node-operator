# Node Operator EKS — Requirements

## Status and source

- **Status:** draft; implementation is blocked on the decisions listed below.
- **Scope:** `node-operator-eks`, one AWS testnet sandbox in `ap-northeast-2`.
- **Source:** `compliance-ops` debrief dated 2026-09-01 and its approved product/architecture records.
- **Boundary:** This project owns EKS infrastructure, node workloads, and non-sensitive evidence export. `compliance-ops` owns evidence normalization, OSCAL evaluation, API, and dashboard. Versioned schemas live in the separately owned `compliance-contracts` package/repository.

## Decisions required before implementation

| ID | Decision | Blocks |
| --- | --- | --- |
| D-1 | **Approved: Hoodi** | resolved 2026-09-01 |
| D-2 | **Approved: Nethermind; choose a Hoodi-compatible stable release at implementation start and pin its OCI `sha256` digest** | resolved 2026-09-01; release selection is recorded with the implementing change |
| D-3 | **Approved: retain non-sensitive normalized evidence for 90 days; retry buffer for at most 24 hours; retain no raw sensitive data** | resolved 2026-09-01 |
| D-4 | **Approved: use the approved sandbox account (supplied out of band), create a dedicated `10.80.0.0/16` VPC with private subnets across two AZs, deny public inbound, and allow only DNS, AWS/approved-telemetry HTTPS, and Hoodi P2P TCP/UDP outbound.** | resolved 2026-09-01; Terraform apply still needs separate authorization |
| D-5 | Defer OSCAL control-to-evidence mappings and freshness thresholds to the separate `compliance-ops` project. | not a Node Operator implementation blocker |
| D-6 | **Approved: balanced two-node EKS configuration—managed EC2 node group `min=2`, `desired=2`, `max=3`; `m7i.2xlarge`-class default; Prysm and Nethermind placed on different nodes in two AZs.** | resolved 2026-09-01 |
| D-7 | **Approved: send evidence to the private Compliance Ops ingestion API through `POST /v1/evidence`, authenticated by exporter-only EKS Pod Identity credentials and SigV4.** The exporter has only `execute-api:Invoke` for that route; it keeps encrypted non-sensitive retry data for at most 24 hours. | resolved 2026-09-01; Compliance Ops owns the API, S3, and PostgreSQL |
| D-8 | **Approved: use GitHub identity `@fjybjinsu` as the required secondary approval identity for sensitive-path, policy-exception, and release-eligibility reviews.** | resolved 2026-09-01; account separation, not independent-human review |
| D-9 | **Approved: OPA blocks all Critical vulnerability findings and High findings with an available fix; it warns on Medium/Low findings. Exceptions require rule, subject, owner, rationale, linked issue, and expiry of at most 30 days.** | resolved 2026-09-01 |
| D-10 | **Approved: CI commands use Bash and `jq`, pass ShellCheck, return structured OPA decisions, pin tools/actions to immutable versions or commit SHAs, and retain only non-sensitive CI evidence for 90 days.** | resolved 2026-09-01 |

## User stories

### US-1: Secure testnet platform

**As a** platform engineer  
**I want** reproducible, private EKS infrastructure for the approved testnet  
**So that** node workloads run only on a constrained sandbox platform.

#### Acceptance criteria (EARS)

1. WHEN Terraform is planned with approved environment inputs, THE SYSTEM SHALL define EKS only in `ap-northeast-2`, inside the dedicated `10.80.0.0/16` VPC using private workload networking and managed Linux EC2 node groups.
2. WHEN persistent storage is requested by an approved workload, THE SYSTEM SHALL provision dynamically managed encrypted EBS volumes through the EBS CSI driver.
3. WHEN the cluster is provisioned, THE SYSTEM SHALL maintain two desired managed nodes across two AZs, with an autoscaling maximum of three nodes and an `m7i.2xlarge`-class default instance type exposed as a validated variable.
4. WHEN a workload needs AWS access, THE SYSTEM SHALL use a dedicated Kubernetes service account associated through EKS Pod Identity and a least-privilege IAM role.
5. WHEN the platform is configured, THE SYSTEM SHALL enable CloudTrail and AWS Config evidence sources without granting workload IAM principals permission to mutate them.
6. THE SYSTEM SHALL NOT create public node endpoints, use Fargate for EBS-backed workloads, or define mainnet resources.

### US-2: Constrained node workloads

**As a** node operator  
**I want** consensus and execution clients deployed independently  
**So that** testnet synchronization and health can be observed without coupling their lifecycles.

#### Acceptance criteria (EARS)

1. WHEN the implementation change selects the approved Hoodi-compatible Nethermind stable release, THE SYSTEM SHALL render separate Prysm and Nethermind Kubernetes workloads pinned to Hoodi and immutable image versions.
2. WHEN either workload starts, THE SYSTEM SHALL mount only its own encrypted persistent volume claim and run using a non-root, read-only-root-filesystem security context except for explicitly declared writable mounts.
3. WHEN workloads are scheduled, THE SYSTEM SHALL enforce anti-affinity and node-selection constraints so Prysm and Nethermind run on different nodes; their claims SHALL use respectively 500 GiB/6,000 IOPS/250 MiB/s and 2 TiB/10,000 IOPS/250 MiB/s encrypted `gp3` storage defaults.
4. WHEN a workload is unhealthy, THE SYSTEM SHALL expose liveness, readiness, and startup probes appropriate to that client and SHALL not claim healthy synchronization solely because the process is running.
5. WHEN network traffic is evaluated, THE SYSTEM SHALL apply default-deny NetworkPolicies, deny public inbound, and permit only Hoodi P2P TCP/UDP, DNS, AWS/approved-telemetry HTTPS, and documented intra-cluster flows.
6. THE SYSTEM SHALL NOT deploy validator clients, accept validator keys, create key material, perform validator or mainnet operation, or schedule automatic EBS snapshots for node-chain data.

### US-3: Read-only operational evidence export

**As a** compliance service  
**I want** timestamped, non-sensitive node and platform evidence  
**So that** I can evaluate controls without access to the source environment.

#### Acceptance criteria (EARS)

1. WHEN an allow-listed metric, Kubernetes posture item, AWS Config/CloudTrail event summary, or IaC output is collected, THE SYSTEM SHALL export it through a versioned `compliance-contracts` evidence schema with source identity and collection time.
2. WHEN an event contains a credential, validator key, authentication header, raw sensitive log content, or sensitive payload, THE SYSTEM SHALL exclude or redact it before export.
3. WHEN validated evidence is sent, THE SYSTEM SHALL call only the private Compliance Ops `POST /v1/evidence` ingestion route using SigV4 credentials from an exporter-only EKS Pod Identity role with a route-scoped `execute-api:Invoke` permission.
4. WHEN an evidence delivery is accepted, THE SYSTEM SHALL use the returned `evidenceId` as its idempotency key for retry-safe delivery.
5. WHEN non-sensitive evidence is locally buffered, THE SYSTEM SHALL retain only encrypted retry data for at most 24 hours; the approved 90-day normalized-evidence retention begins after accepted ingestion in Compliance Ops. It SHALL retain no raw sensitive data and SHALL NOT write directly to Compliance Ops S3 or PostgreSQL storage.
6. WHEN evidence collection or export fails, THE SYSTEM SHALL emit a non-sensitive health signal and preserve no retry payload containing excluded fields.
7. THE SYSTEM SHALL NOT expose a route, job, or IAM action that changes AWS, EKS, Kubernetes, or Compliance Ops source state during evidence collection.

### US-4: Supply-chain and policy assurance

**As a** security engineer  
**I want** infrastructure and manifests checked before delivery  
**So that** an unsafe configuration does not reach a deployable artifact.

#### Acceptance criteria (EARS)

1. WHEN source, workflow, Terraform, or Kubernetes files change, THE SYSTEM SHALL collect structured open-source evidence from Gitleaks, OSV-Scanner, Semgrep, Zizmor, Checkov, and the required formatting/validation tools without deploying them.
2. WHEN structured evidence is collected, THE SYSTEM SHALL normalize it with commit-SHA or artifact-digest provenance and evaluate it with version-controlled, tested OPA/Rego policy.
3. WHEN OPA classifies a violation as `block`, or required evidence is absent/incomplete, THE SYSTEM SHALL fail the pull-request gate and publish CLI and SARIF/JSON evidence for review.
4. WHEN an image or IaC artifact is produced or referenced, THE SYSTEM SHALL create an SBOM and collect scan, signature, and provenance evidence before a future release gate evaluates it.
5. WHEN CI authenticates to AWS in a later separately authorized delivery workflow, THE SYSTEM SHALL use GitHub OIDC with a narrowly scoped role; no static cloud credential SHALL be stored in this repository.
6. WHEN a policy check detects privileged containers, unapproved images, public exposure, missing encryption, over-broad IAM, unsafe workflow configuration, secrets, or an expired exception, THE SYSTEM SHALL fail the applicable gate.
7. WHEN a CI workflow changes, THE SYSTEM SHALL express only pipeline control flow in YAML and invoke one-purpose, locally testable scripts for collection, normalization, policy evaluation, and reporting.
8. WHEN a pull request changes `policy/**`, `.github/workflows/**`, release configuration, or the exception register, THE SYSTEM SHALL require review by `@fjybjinsu` and SHALL reject author self-approval.
9. WHEN vulnerability evidence is evaluated, THE SYSTEM SHALL block Critical findings and High findings with an available fix, warn on Medium/Low findings, and reject any exception lacking the required fields or exceeding 30 days.
10. WHEN a CI command is added, THE SYSTEM SHALL be a ShellCheck-clean Bash script using `jq` for JSON shaping and SHALL return OPA decisions with `id`, `class`, `reason`, `subject`, and `evidence_ref`.

## Non-functional requirements

- All resource names, account IDs, CIDRs, image references, and endpoints are input variables or approved configuration; no secrets appear in source, state fixtures, logs, or evidence examples.
- Every exported evidence record has a schema version, stable source identifier, collection timestamp, and provenance reference.
- Infrastructure and workload configuration must be reproducible from version-controlled inputs and support offline validation without AWS credentials.
- Checkov scans `infra/terraform` with the Terraform framework and `deploy` with the Kubernetes framework. Its JSON is evidence consumed by OPA; policy exceptions live in a reviewed, expiring register rather than unreviewed Checkov suppressions, `soft_fail`, or a baseline.
- The policy set is repository-local, protected by CODEOWNERS, has passing/failing Rego fixtures, and makes decisions from structured evidence only. A missing, failed, or truncated evidence collection is non-compliant.
- Workflow YAML SHALL NOT contain multiline shell implementations, embedded policy logic, JSON transformation, or copied scanner flags. Reusable CI behavior lives in `scripts/ci/`, with shared functions extracted only after a second caller exists.
- Third-party actions and tools are pinned to a full commit SHA or immutable release version. Only non-sensitive JSON/SARIF evidence is retained for 90 days; raw scanner logs and secret candidates are excluded.
- Source-environment mutation, AWS access, deployment, publishing, merging, secret changes, and any validator/mainnet action require separate task-level authorization.

## Out of scope

- Compliance Ops persistence, OSCAL control evaluation, read-only API, dashboard, and control-to-evidence freshness decisions.
- Mainnet, validator/key management, multi-region HA, service mesh, Kafka, Vault, and AWS provisioning/apply.
