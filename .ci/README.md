# Build and security inputs

This directory contains release inputs, not disposable CI output. Dockerfiles,
patches, source locks, scanner settings and approved digest lists must remain
versioned to reproduce and verify the published images.

| Group | Purpose |
| --- | --- |
| `scanners`, `toolchains` | Pinned CI scanners and reusable build/tool containers |
| `fence-security` | Fence-only SAST and isolated real-process DAST assets |
| `validator-signing-fence`, `vault-audit-relay` | First-party runtime image builds |
| `prysm-*`, `nethermind-runtime`, `web3signer-hardened`, `postgres-runtime` | Client, signer and database builds, including dependency patches |
| `vault-*-hardened`, `vault-runtime-*` | Vault build inputs and vulnerability applicability evidence |
| `validator-*-probe`, `upcheck-python-runtime` | Runtime diagnostic images |
| `validator`, `gitops`, `dast` | Approved image/artifact digests consumed by release and verification scripts |

`Dockerfile.dockerignore` files are per-Dockerfile build-context allowlists;
they are intentionally separate. Do not merge them into a permissive global
ignore file. Some retained recipes document an existing image without an
automatic publisher; lack of a workflow reference alone does not imply disuse.

## Required workflow ownership

- `CI Policy / policy`: Rego, Terraform policy and rendered manifest tests.
- `CI Policy Foundation / policy-foundation`: evidence normalization, PR gate and
  baseline filtering contracts, private target contract and suite ownership.
- `CI Quality / quality`: script quality and remaining implementation tests;
  still requires the Fence security workflow to succeed.

Workflow paths and required job identities remain stable: release eligibility
validates their provenance. All three workflows still execute on PRs and main
pushes. No signing, scan, approval or release gate is removed by deduplication.

## English presentation conventions

Workflow display titles use `CI <Subject>`, `Release <Artifact>` or
`Mirror <Artifact>`. Named steps use `<Phase> | <Description>`, with `Prepare`,
`Check`, `Build`, `Evidence` or `Publish` as the phase. Descriptions retain the
specific check or action; these labels do not imply that a step has passed.

Keep workflow filenames, job IDs, and published required-check contexts stable.
`CI Security` and `CI Evidence Review Signal` are also event-routing identities,
so their exact titles must remain aligned with workflow-run consumers.

Workflow-referenced test, verification and scan entrypoints describe their
scope in an English `Check objective:` header. These comments distinguish
offline contract tests from runtime scans; they are not execution evidence.
