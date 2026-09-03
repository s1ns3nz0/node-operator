# Node Operator evidence search handoff

## Objective

Provide SIEM-like search and timeline visibility for Node Operator CI and
runtime evidence without storing secrets or treating the search index as the
authoritative archive.

## Required pipeline

```text
Node Operator CI
  -> canonical evidence envelope
  -> compliance-ops ingestion API
  -> immutable S3 archive
  -> OpenSearch metadata index
  -> compliance-ops search API/dashboard
```

S3 is the authoritative evidence archive. OpenSearch is a derived, searchable
index and must be rebuildable from S3 objects.

## Ingestion contract

The API must validate `@s1ns3nz0/compliance-contracts@1.0.0` envelopes before
persisting them. Each accepted event includes:

- `schema_version`
- `repo`, `commit_sha`, and `workflow_run_id`
- `tool`, `tool_version`, and `collected_at`
- `result.status` and non-sensitive findings
- artifact `sha256` and S3 object key

Ingestion must be idempotent on `(repo, commit_sha, workflow_run_id, tool)` and
must reject malformed or unsupported schema versions fail-closed.

## S3 archive

Store the complete approved non-sensitive envelope under:

```text
repo=<repo>/commit=<sha>/run=<run-id>/normalized/<tool>.json
```

Use a private versioned SSE-KMS bucket with TLS-only access and retention/Object
Lock controls. Never overwrite an existing object for the same key; revisions
must be append-only. Terraform state, raw CI logs, Vault tokens, kubeconfigs,
cloud credentials, and secret values must be rejected before upload.

## OpenSearch index

Index only searchable metadata and normalized findings:

```text
repo, commit_sha, workflow_run_id, tool, tool_version,
rule_id, severity, resource_address, status, collected_at,
artifact_sha256, s3_object_key
```

The index must support filtering by commit SHA, workflow run, tool, rule ID,
severity, resource address, status, and time range. Provide a timeline view and
aggregations for failures by tool, severity, and rule. Do not index secret
values, token material, Terraform state, kubeconfig contents, or raw logs.

## API surface

- `POST /v1/evidence` — validate, archive, and index an envelope
- `GET /v1/evidence` — filtered search with pagination and time bounds
- `GET /v1/evidence/{id}` — metadata plus signed/authorized S3 retrieval reference
- `GET /v1/evidence/summary` — counts by status, tool, severity, and time range

Search responses must include the canonical event identity and artifact hash so
callers can verify that an S3 object matches the indexed record.

## Security and operations

- Authenticate ingestion with the approved service identity; do not accept
  developer PATs or arbitrary bearer tokens in evidence payloads.
- Enforce tenant/repository authorization on both search and archive retrieval.
- Emit audit events for ingestion, search, and archive access without logging
  request secrets or payload values.
- Apply rate limits, payload size limits, schema validation, and replay
  protection at the API boundary.
- Define index lifecycle/retention separately from the S3 compliance retention.
- Add reindex and restore tests proving OpenSearch can be rebuilt from S3.

## Acceptance checklist

- Valid T-1/T-6 envelopes ingest exactly once.
- Invalid schema versions and forbidden fields fail closed.
- S3 object hash equals the indexed `artifact_sha256`.
- Search returns results by commit, run, severity, rule, resource, and time.
- S3 remains the source of truth when the index is deleted and rebuilt.
- No secrets, Terraform state, Vault material, kubeconfigs, or raw CI logs are
  present in S3 evidence objects, OpenSearch documents, or API responses.
