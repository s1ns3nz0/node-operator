#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
for file in \
  "$root/cmd/vault-audit-relay/main.go" \
  "$root/.ci/vault-audit-relay/Dockerfile" \
  "$root/infra/terraform/vault-audit-relay-ecr.tf" \
  "$root/.github/workflows/vault-audit-relay-image-release.yml"; do
  test -f "$file" || { printf 'missing Vault audit relay asset: %s\n' "$file" >&2; exit 1; }
done

grep -Fq 'net.Listen("unix"' "$root/cmd/vault-audit-relay/main.go"
grep -Fq 'discarded non-JSON Vault audit record' "$root/cmd/vault-audit-relay/main.go"
grep -Fqx 'FROM scratch' "$root/.ci/vault-audit-relay/Dockerfile"
grep -Fq 'USER 100:1000' "$root/.ci/vault-audit-relay/Dockerfile"
grep -Fq 'enable_vault_audit_relay_ecr_publisher' "$root/infra/terraform/vault-audit-relay-ecr.tf"
grep -Fq 'image_tag_mutability = "IMMUTABLE"' "$root/infra/terraform/vault-audit-relay-ecr.tf"
grep -Fq 'scan_on_push = true' "$root/infra/terraform/vault-audit-relay-ecr.tf"
grep -Fq 'vault-audit-relay-ecr-publish' "$root/infra/terraform/vault-audit-relay-ecr.tf"
grep -Fq 'ecr:PutImage' "$root/infra/terraform/vault-audit-relay-ecr.tf"
grep -Fq 'environment: vault-audit-relay-ecr-publish' "$root/.github/workflows/vault-audit-relay-image-release.yml"
grep -Fq 'docker build --pull' "$root/.github/workflows/vault-audit-relay-image-release.yml"
grep -Fq 'REPLACE_WITH_PRIVATE_VAULT_AUDIT_RELAY_DIGEST' "$root/docs/gitops/vault-values.example.yaml"
printf 'PASS: Vault audit relay is private, immutable, non-root, and socket-only.\n'
