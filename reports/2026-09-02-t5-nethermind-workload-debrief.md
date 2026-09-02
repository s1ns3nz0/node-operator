# T-5 Clean-Room Debrief: Nethermind Hoodi Workload

## Scope

Reviewed only the T-5 task bundle, the Nethermind deployment and policy changes,
the Conftest CI-script change, and recorded evidence. No files were modified.

## Observed evidence

- The overlay defines one Hoodi Nethermind StatefulSet using the immutable
  `nethermind/nethermind` digest recorded in the task evidence.
- The workload uses a dedicated service account with API-token mounting
  disabled, hardened pod/container security settings, P2P probes, and required
  hostname anti-affinity from Prysm.
- Its persistent claim requests `2Ti` from an encrypted gp3 StorageClass with
  10,000 IOPS, 250 MiB/s throughput, KMS alias use, and retention.
- The policy suite includes secure and insecure fixtures and unit tests
  covering eight deny identifiers. CI now runs secure fixtures and requires
  insecure fixtures to fail.
- Recorded successful checks: local Kustomize rendering, YAML parsing, and
  `npm run harness:check`.

## Validation limitations

- OPA, Conftest, and ShellCheck were unavailable locally. Rego tests and
  Conftest fixture checks were implemented but not executed.
- `npm run harness:verify` was partial for those unavailable tools and an
  intentionally incomplete pre-existing normalizer fixture.
- No deployment, AWS access, cluster access, secret access, image publishing,
  or validator operation occurred.

## Inference

The reviewed manifests and static policies provide a credible local contract
for isolation, storage, image pinning, and restricted egress. They do not
establish runtime enforcement: that requires OPA/Conftest execution and an
approved deployment-time validation environment. Gateway labels, default-deny
prerequisites, node labels, KMS-alias resolution, and actual network-provider
behavior remain unverified external dependencies.

## Recommended completion gate

Run Nethermind Rego and Conftest checks in CI or a provisioned validation
environment, run ShellCheck, and retain the resulting non-sensitive evidence.
Deployment or infrastructure access remains out of scope.
