# Node Operator EKS — Design

## Architecture

```text
Terraform modules ──> private EKS + managed EC2 node groups + EBS CSI
                         │
                         ├── Prysm workload ── encrypted PVC
                         ├── Execution-client workload ── encrypted PVC
                         ├── OTel Collector (allow-list/filter)
                         └── AWS Config / CloudTrail / IaC evidence adapters
                                      │
                           versioned compliance-contracts
                                      │
                              Compliance Ops (external)
```

No component in this repository calls Compliance Ops storage or an AWS/EKS mutation API. The outbound evidence integration is a contract boundary; a transport adapter is selected only after the contract package specifies its authenticated endpoint and delivery semantics.

## Components

| Component | Responsibility | Must not do |
| --- | --- | --- |
| `infra/terraform` | VPC input validation, private EKS, node groups, KMS/EBS CSI, Pod Identity, AWS Config and CloudTrail configuration | apply resources under this spec; place account IDs or credentials in source |
| `deploy/base` | Namespace, service accounts, network policies, resource limits, workload hardening | deploy a validator or mainnet workload |
| `deploy/prysm` | Network-selected Prysm StatefulSet, PVC, probes and allowed metrics | contain validator keys or a writable root filesystem |
| `deploy/execution-client` | Hoodi-compatible stable Nethermind StatefulSet, PVC, probes and allowed metrics, pinned to an OCI digest | use a floating image tag |
| `telemetry` | OTel collector configuration, allow-listing, redaction and exporter health | forward raw logs or credential-bearing data |
| `packages/evidence-exporter` | Translate allowed inputs to `compliance-contracts` evidence envelopes; submit signed `POST /v1/evidence` requests; hold encrypted non-sensitive retry data for at most 24 hours | own OSCAL rules or persist directly to Compliance Ops S3/PostgreSQL records |
| `policy/**` | versioned Rego rules, tier data, expiring exceptions, fixtures, and CODEOWNERS-protected policy ownership | embed policy decisions in workflow shell conditionals |
| `.github/workflows` | declare trigger, permissions, job dependencies, pinned actions, and calls to `scripts/ci/*`; make the CI flow readable at a glance | contain duplicated multiline shell logic, JSON transforms, or policy decisions |
| `scripts/ci` | one-purpose commands for evidence collection, normalization, OPA evaluation, and publication; local fixture-testable shared behavior | hide job ordering, permissions, or workflow authorization decisions |

## Contracts

This project imports versioned contracts rather than duplicating types. The minimum evidence envelope required from `compliance-contracts` is:

```ts
type EvidenceEnvelope<T> = {
  schemaVersion: string;
  evidenceId: string;
  source: { kind: 'aws-config' | 'cloudtrail' | 'iac' | 'kubernetes' | 'otel'; id: string };
  collectedAt: string; // RFC 3339 UTC
  provenance: { reference: string; collectorVersion: string };
  data: T; // validated allow-listed payload
};
```

The exporter validates payloads against the imported schema before sending. Invalid or redaction-failed records are dropped, counted, and represented only by non-sensitive exporter health metrics. It submits only `POST /v1/evidence` to the private Compliance Ops ingestion API, signing requests with SigV4 credentials from its dedicated EKS Pod Identity role. The role grants only route-scoped `execute-api:Invoke`; it has no S3, PostgreSQL, or broader AWS mutation permission. A `202 Accepted` response provides `evidenceId`, which the exporter uses for idempotent retries from an encrypted, non-sensitive 24-hour queue.

## Platform design

- Terraform receives the approved sandbox account through a non-committed input and validates region `ap-northeast-2`. It creates the dedicated `10.80.0.0/16` VPC with private subnets spanning two AZs.
- The managed node group has `min=2`, `desired=2`, and `max=3`. Its validated default is `m7i.2xlarge`-class (8 vCPU/32 GiB); the concrete available family remains a variable so the approved capacity class is portable across availability zones.
- Workload subnets are private. Public inbound is denied; security groups and NetworkPolicies permit only Hoodi P2P TCP/UDP, DNS, AWS/approved-telemetry HTTPS, and documented intra-cluster flows.
- EBS CSI is configured for encrypted PVCs. Pod Identity uses one role per service account and no node-role privilege escalation.
- Prysm and Nethermind are separate StatefulSets with required anti-affinity/node selection across two AZs. Prysm uses an encrypted 500 GiB `gp3` PVC provisioned at 6,000 IOPS and 250 MiB/s; Nethermind uses an encrypted 2 TiB `gp3` PVC provisioned at 10,000 IOPS and 250 MiB/s. Node chain-data volumes receive no automatic snapshots because this is a keyless, re-syncable testnet environment.
- `network` is Hoodi. The implementing change selects the current Hoodi-compatible Nethermind stable release and records its OCI image digest; peer ports, telemetry endpoints, and retention policy remain environment overlays pending D-3–D-4.

## Data flow

1. IaC, EKS posture, AWS evidence summaries, and allow-listed metrics are collected from declared sources.
2. The collector filters fields against an explicit allow-list; redaction happens before any export buffer or log statement.
3. The exporter stamps source/provenance/collection time and validates an `EvidenceEnvelope`.
4. The exporter sends only the validated envelope to Compliance Ops through the signed ingestion route. Node Operator retains only encrypted retry buffers for at most 24 hours; after accepted ingestion, Compliance Ops owns the approved 90-day normalized-evidence retention, S3/PostgreSQL persistence, and evaluation independently.
5. Exporter health is available locally for operational diagnosis without returning prohibited source payloads.

## Security and failure behavior

- IAM policies are generated from a documented action/resource allow-list and policy-tested for denied mutation actions.
- CI runs the evidence producers described in `docs/policy-as-code.md`, including formatting, offline Terraform validation, Checkov, Gitleaks, OSV-Scanner, Semgrep, Zizmor, and later Syft/Grype, Cosign, and SLSA provenance. A normalizer binds evidence to the commit SHA or artifact digest and OPA makes the final gate decision.
- Each workflow calls the scripts in `scripts/ci/` rather than implementing tool invocation, input shaping, or policy branching inline. Workflows retain only orchestration details required to understand authorization and execution order.
- CI fails closed if evidence is missing/incomplete or OPA returns a blocking decision. It fails on public exposure, unencrypted volume configuration, privileged workload settings, mutable images, missing resource constraints, unsafe workflow definitions, secrets, or policy violations. Exceptions are structured data with owner, rationale, linked issue, subject, and expiry; OPA rejects expired/incomplete exceptions.
- `CODEOWNERS` assigns `@fjybjinsu` as required owner for `policy/**`, `.github/workflows/**`, release configuration, and the exception register. Branch protection requires that review and disallows author self-approval. This is an account-separation control for the portfolio, not a claim of independent-human review.
- OPA classifies every Critical vulnerability as `block`; a High finding is `block` when a fixed version is available; Medium/Low findings are `warn`. An exception is valid only with rule, subject, owner, rationale, linked issue, and an RFC 3339 expiry no later than 30 days after approval.
- Missing collection permissions, unreachable destinations, stale source data, and schema validation errors result in non-sensitive health/error signals. They never trigger infrastructure remediation or source mutation.
- The infrastructure's telemetry data minimization configuration is tested with fixtures containing prohibited fields.

## Alternatives considered

- **Single combined repository:** rejected; it would duplicate the evidence/control contract and blur the read-only boundary.
- **Fargate nodes:** rejected; EBS-backed persistent volumes are required for node data.
- **Static AWS credentials:** rejected; future CI access must use GitHub OIDC and explicit authorization.

## Decision gates

T-1 through T-4 may scaffold and validate contracts/configuration without external actions. Hoodi and Nethermind are approved, with the immutable Nethermind release/digest selected at task start. Retention is 90 days for normalized non-sensitive evidence and 24 hours for retry buffers. Any Terraform plan against an account is blocked by D-4 and authorization.
