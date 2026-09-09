## Fix

Patch only Vault Server/Agent gRPC1.83.1 to1.83.2 for
[GHSA-2v4p-qf9q-27wj](https://github.com/advisories/GHSA-2v4p-qf9q-27wj).
The module diff is one version line and two new checksum lines. Both recipes
and the source lock verify the new exact hashes using the same pinned Go
toolchain. No High exception or scanner suppression is introduced.

## Actual local verification

- Each affected image built once with Docker caches; upstream command/Agent tests passed.
- Pinned Grype0.118.0, DB2026-09-09T06:31:00Z: both C0/H0/M3/U1, zero matches for the gRPC advisory, SBOMs show gRPC1.83.2. Raw evidence retained.
- New Server passed synthetic Raft upgrade, retained KV, snapshot restore and token-revocation checks.
- New Agent passed Kubernetes auth/KV template/non-raw audit compatibility against both Vault1.20.4 and the exact new Vault2.1.0 server.
- New binary hashes bound to complete dependency exports; affected legacy OpenPGP package tree remains absent. Agent export reused the cached build, not another compilation.
- Source lock regression tests, ShellCheck, harness validation and independent Terra source/evidence review performed; exact outcomes and hashes are in the task evidence.

## Risk and scope

The old Server/Agent digests remain explicitly documented as ineligible after
the new High finding. The only added allowlist entry is the exact new server
in the **synthetic compatibility fixture**, not a production selection.
The Raft fixture accepts only an immutable local image ID for candidate tests.

No image is published or signed, no production candidate/applicability
selection is changed, and no Vault/validator/PVC/custody/IAM/GitOps resource is
modified. Existing Medium and Unknown findings are retained. New bytes require
new reviewed proof bindings and a separate publication/promotion step. Local
Docker metadata is not represented as trusted GitHub build provenance.
